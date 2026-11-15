#!/bin/bash
# =====================================================================
# provision.sh - builds the "Uploadry" vulnerable target inside the VM.
# Runs as root during `limactl start` (provision mode: system).
# Idempotent: safe to re-run / used by the lab reset helper.
# =====================================================================
set -euo pipefail

LAB_SRC="/opt/lab/webapp"       # repo webapp dir, mounted read-only
DOCROOT="/var/www/html"

echo "[*] Installing Apache + PHP ..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 php libapache2-mod-php >/dev/null

echo "[*] Deploying the SnapShare web app ..."
rm -rf "$DOCROOT"
mkdir -p "$DOCROOT"
cp -r "$LAB_SRC/." "$DOCROOT/"
find "$DOCROOT" \( -name '.DS_Store' -o -name '._*' \) -delete    # strip macOS cruft the build tar may add

# --- Info-disclosure: leftover source backup served as plain text -----
# (Apache serves .bak as text/plain, leaking the admin credentials.)
cp "$DOCROOT/admin/config.php" "$DOCROOT/admin/config.php.bak"

# --- Uploads dir must be writable by the web server -------------------
mkdir -p "$DOCROOT/uploads"
chown -R www-data:www-data "$DOCROOT/uploads"
chmod 775 "$DOCROOT/uploads"

# Make sure .phtml (and friends) are executed as PHP so the blacklist
# bypass actually yields code execution.
cat >/etc/apache2/conf-available/lab-phtml.conf <<'EOF'
<FilesMatch "\.(phtml|php3|php4|php5|php7|pht|phar)$">
    SetHandler application/x-httpd-php
</FilesMatch>
EOF
a2enconf lab-phtml >/dev/null 2>&1 || true

# Expose the PHP version in the X-Powered-By header so the room's
# fingerprinting task is solvable (Ubuntu ships this Off for the Apache SAPI;
# leaking it is a common real-world misconfiguration).
sed -i 's/^expose_php = Off/expose_php = On/' /etc/php/*/apache2/php.ini || true

echo "[*] Creating the 'michael' system account (reused DB password) ..."
if ! id michael >/dev/null 2>&1; then
    useradd -m -s /bin/bash michael
fi
echo 'michael:Photos#Backup2023' | chpasswd

# --- Privilege escalation: NOPASSWD sudo on a GTFOBins binary ---------
cat >/etc/sudoers.d/michael <<'EOF'
michael ALL=(root) NOPASSWD: /usr/bin/find
EOF
chmod 440 /etc/sudoers.d/michael

# --- Flags (TryHackMe format, canonical user.txt / root.txt) ---------
# Real flags are injected at build time via the USER_FLAG / ROOT_FLAG env
# vars; the defaults below are redacted placeholders so the public repo stays
# spoiler-free. (An empty value also falls back to the placeholder.)
USER_FLAG="${USER_FLAG:-REDACTED__set_USER_FLAG_env_at_build}"
ROOT_FLAG="${ROOT_FLAG:-REDACTED__set_ROOT_FLAG_env_at_build}"
echo "$USER_FLAG" > /home/michael/user.txt
chown michael:michael /home/michael/user.txt
chmod 750 /home/michael          # www-data must not read user.txt before becoming michael
chmod 640 /home/michael/user.txt
echo "$ROOT_FLAG" > /root/root.txt
chmod 600 /root/root.txt

echo "[*] Enable password SSH + root login (for platform maintenance access) ..."
# Root password for the hosting platform's maintenance SSH (e.g. TryHackMe).
# Injected at build time via ROOT_PASS. root over SSH is for maintenance, not part
# of the intended path: without ROOT_PASS root keeps no password and cannot log in
# over SSH (no guessable default such as "changeme").
if [ -n "${ROOT_PASS:-}" ]; then
    echo "root:${ROOT_PASS}" | chpasswd
    ROOT_LOGIN=yes
else
    echo "[!] ROOT_PASS not set: root login over SSH stays disabled"
    passwd -l root >/dev/null
    ROOT_LOGIN=no
fi

# Password auth must survive cloud-init's FIRST boot on the target platform: the
# image is cloud-init-cleaned at build, so cloud-init re-runs there and writes
# /etc/ssh/sshd_config.d/50-cloud-init.conf from ssh_pwauth — which would set
# 'PasswordAuthentication no' and lock root. Tell cloud-init not to.
mkdir -p /etc/cloud/cloud.cfg.d
cat >/etc/cloud/cloud.cfg.d/99-lab-ssh.cfg <<'EOF'
ssh_pwauth: true
disable_root: false
EOF

# Our own sshd drop-in; '00-' sorts first, so it wins sshd's first-match rule.
mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/00-lab.conf <<EOF
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin ${ROOT_LOGIN}
EOF

# Flip any value baked into the main config or the other drop-ins (the Ubuntu
# cloud image ships 'PasswordAuthentication no').
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
find /etc/ssh/sshd_config.d -name '*.conf' ! -name '00-lab.conf' \
    -exec sed -i 's/^[#[:space:]]*PasswordAuthentication .*/PasswordAuthentication yes/' {} + 2>/dev/null || true
systemctl restart ssh || systemctl restart sshd || true

echo "[*] Restarting Apache ..."
systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

# --- Networking: AWS-native (cloud-init) + a DHCP fallback ---------------
# THM converts the OVA to an AWS AMI and boots it on EC2, where the *Ec2*
# cloud-init datasource (169.254.169.254 metadata) configures the primary NIC.
# So we let cloud-init OWN networking — we do NOT disable it and we do NOT drop
# the Ec2 datasource — and let it write the correct netplan for whatever the
# interface is named on the target (eth0 on Xen t2, ens5 on Nitro, etc.).
# We only make the datasource search order explicit (Ec2 for AWS/THM, NoCloud
# for local seed-based testing) and remove any leftovers from the previous
# "network: disabled" experiment.
mkdir -p /etc/cloud/cloud.cfg.d
printf 'datasource_list: [ Ec2, NoCloud, None ]\n' > /etc/cloud/cloud.cfg.d/90-datasource.cfg
rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
rm -f /etc/netplan/01-net-dhcp.yaml

# Belt-and-suspenders: a boot-time one-shot that only acts if NOTHING else gave
# the box an IPv4 address (e.g. the datasource didn't configure the NIC). It
# never fights cloud-init when cloud-init succeeds — it checks first — so it is
# safe on AWS, VMware and QEMU alike, and it is what makes this build differ
# from a plain stock-cloud-init image.
cat >/usr/local/sbin/lab-netfallback.sh <<'EOF'
#!/bin/bash
# Fallback DHCP + boot network diagnostics. Every line is mirrored to the serial
# console (/dev/ttyS0) when present, so the hosting platform's instance system
# log (AWS/EC2 — what TryHackMe can pull) shows the network story even when the
# box is unreachable over IP. Harmless locally (no writable ttyS0 -> journal only).
SER=/dev/ttyS0
log(){ echo "lab-net: $*"; [ -w "$SER" ] && echo "lab-net: $*" > "$SER" 2>/dev/null || true; }
log "boot diag $(date -u 2>/dev/null)"
log "cloud-init: $(cloud-init status 2>/dev/null | tr '\n' ' ')"
log "ifaces: $(ls /sys/class/net 2>/dev/null | tr '\n' ' ')"
# Give the normal path (cloud-init/netplan/networkd) ~60s to obtain an IP.
for _ in $(seq 1 20); do
    if ip -4 addr show scope global 2>/dev/null | grep -q 'inet '; then
        log "have global IPv4: $(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2,$4}' | tr '\n' ' ')"
        exit 0
    fi
    sleep 3
done
# Still no global IPv4 -> re-apply whatever netplan config exists.
log "no global IPv4 after 60s -> re-applying netplan"
netplan apply 2>/dev/null || true
sleep 5
if ip -4 addr show scope global 2>/dev/null | grep -q 'inet '; then
    log "global IPv4 after netplan apply: $(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2,$4}' | tr '\n' ' ')"
    exit 0
fi
# Nothing at all -> write a DHCP netplan for the first real ethernet and apply.
IFACE=$(ls /sys/class/net 2>/dev/null | grep -E '^(en|eth)' | head -1)
[ -n "$IFACE" ] || { log "no ethernet iface found"; exit 0; }
log "forcing DHCP on $IFACE"
cat >/etc/netplan/99-lab-fallback.yaml <<NET
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: true
      dhcp-identifier: mac
NET
chmod 600 /etc/netplan/99-lab-fallback.yaml
netplan apply 2>/dev/null || true
command -v dhclient    >/dev/null && dhclient -1 "$IFACE"        2>/dev/null || true
command -v networkctl  >/dev/null && networkctl reconfigure "$IFACE" 2>/dev/null || true
log "final: $(ip -4 -o addr show 2>/dev/null | awk '{print $2,$4}' | tr '\n' ' ')"
EOF
chmod +x /usr/local/sbin/lab-netfallback.sh

cat >/etc/systemd/system/lab-netfallback.service <<'EOF'
[Unit]
Description=Lab fallback DHCP + boot network diagnostics
# Deliberately NOT ordered After/Wants network-online.target: this unit's whole
# job is to rescue the "network never came up" case, and gating it on
# network-online would mean it never runs in exactly that case. It runs after
# cloud-init and networkd have *tried*, then polls for an IP on its own.
After=cloud-init.service systemd-networkd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lab-netfallback.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable lab-netfallback.service >/dev/null 2>&1 || true

# --- VMware Fusion integration + EFI boot fallback -------------------
# open-vm-tools: guest integration + lets `vmrun getGuestIPAddress` work.
# Harmless on non-VMware platforms (the service simply no-ops).
apt-get install -y open-vm-tools >/dev/null 2>&1 || true
# Removable-media EFI fallback: copy the arm64 bootloader to the generic
# \EFI\BOOT\BOOTAA64.EFI path, so the image boots under firmwares that do
# not carry an NVRAM boot entry (e.g. VMware). Only triggers on arm64.
if [ -f /boot/efi/EFI/ubuntu/shimaa64.efi ]; then
    mkdir -p /boot/efi/EFI/BOOT
    cp -f /boot/efi/EFI/ubuntu/shimaa64.efi /boot/efi/EFI/BOOT/BOOTAA64.EFI
    cp -f /boot/efi/EFI/ubuntu/grubaa64.efi /boot/efi/EFI/BOOT/grubaa64.efi 2>/dev/null || true
fi

# --- Serial console on EVERY build (console / system-log visibility) ---
# AWS/EC2 — and therefore TryHackMe — read the guest's *serial* console (ttyS0)
# for the instance system log. Without ttyS0 on the kernel cmdline that log is
# blank and the lab-netfallback boot diagnostics above reach no one who could
# read them. tty0 stays too, so VMware's graphical console still shows the boot
# (and doesn't freeze at "Exiting boot services"). Previously LAB_FUSION-gated,
# which is exactly why the x86/AWS image was undiagnosable.
sed -i 's#^GRUB_CMDLINE_LINUX_DEFAULT=.*#GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0,115200 console=tty0"#' /etc/default/grub
update-grub >/dev/null 2>&1 || true
systemctl enable getty@tty1 >/dev/null 2>&1 || true

# Record the exact PHP version (used for the room's fingerprinting task
# and the submission write-up). Printed to the console/serial log.
echo "[i] PHP version: $(php -v | head -1)"
echo "[+] Uploadry target is ready."
