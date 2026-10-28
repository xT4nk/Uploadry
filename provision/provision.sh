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
USER_FLAG="${USER_FLAG:-THM{REDACTED___set_USER_FLAG_at_build}}"
ROOT_FLAG="${ROOT_FLAG:-THM{REDACTED___set_ROOT_FLAG_at_build}}"
echo "$USER_FLAG" > /home/michael/user.txt
chown michael:michael /home/michael/user.txt
chmod 644 /home/michael/user.txt
echo "$ROOT_FLAG" > /root/root.txt
chmod 600 /root/root.txt

echo "[*] Allow password SSH login (so michael can be used over SSH too) ..."
# Ubuntu cloud images disable password auth in
# /etc/ssh/sshd_config.d/60-cloudimg-settings.conf, and sshd honours the
# FIRST matching value — so (a) flip any existing drop-in to 'yes', and
# (b) add an early-sorting 00- drop-in that wins the first-match race.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
find /etc/ssh/sshd_config.d -name '*.conf' -exec sed -i 's/^[#[:space:]]*PasswordAuthentication .*/PasswordAuthentication yes/' {} + 2>/dev/null || true
printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/00-lab.conf
rm -f /etc/ssh/sshd_config.d/99-lab.conf
systemctl restart ssh || systemctl restart sshd || true

echo "[*] Restarting Apache ..."
systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

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

# --- Fusion-only tweaks (console visibility + reliable DHCP) ---------
# Gated on LAB_FUSION=1 so the x86/THM (AWS) image is left untouched.
if [ "${LAB_FUSION:-0}" = "1" ]; then
    # Show the boot + a login prompt on VMware's graphical console, not
    # only on the serial line (otherwise the screen freezes at
    # "Exiting boot services" even though the kernel is booting).
    sed -i 's#^GRUB_CMDLINE_LINUX_DEFAULT=.*#GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0,115200 console=tty0"#' /etc/default/grub
    update-grub >/dev/null 2>&1 || true
    systemctl enable getty@tty1 >/dev/null 2>&1 || true

    # Deterministic DHCP on whatever the NIC is named (vmxnet3 -> ens*),
    # independent of cloud-init's datasource detection under VMware.
    echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    cat > /etc/netplan/01-fusion-dhcp.yaml <<'NETPLAN'
network:
  version: 2
  ethernets:
    alleth:
      match:
        name: "e*"
      dhcp4: true
      dhcp-identifier: mac
NETPLAN
    chmod 600 /etc/netplan/01-fusion-dhcp.yaml
    netplan generate >/dev/null 2>&1 || true
fi

# Record the exact PHP version (used for the room's fingerprinting task
# and the submission write-up). Printed to the console/serial log.
echo "[i] PHP version: $(php -v | head -1)"
echo "[+] Uploadry target is ready."
