#!/bin/bash
# =====================================================================
# build-arm64-fusion.sh — build the Uploadry target as an ARM64 VM and
# package it as a VMware Fusion VM (.vmwarevm) for local testing on
# Apple Silicon (attack it from a Kali VM on the same Fusion network).
#
# Uses QEMU with the HVF accelerator (native arm64 — fast, no emulation).
# Reuses provision/provision.sh unchanged via cloud-init.
#
#   ./build/build-arm64-fusion.sh
#
# Output: dist/Progress-Uploadry-arm64.vmwarevm
# =====================================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ART="${ART_DIR:-${TMPDIR:-/tmp}/uploadry-build/arm64}"
DIST="$REPO/dist"
IMG_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-arm64.img"
DISK_GB=10
VMNAME="Progress-Uploadry-arm64"
EDK2_CODE=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
EDK2_VARS=/opt/homebrew/share/qemu/edk2-arm-vars.fd

mkdir -p "$ART" "$DIST"
cd "$ART"

echo "[*] 1/6 Fetching Ubuntu 22.04 arm64 cloud image ..."
[ -f base.img ] || curl -fL --retry 3 -o base.img "$IMG_URL"
cp -f base.img disk.qcow2
qemu-img resize disk.qcow2 "${DISK_GB}G"

echo "[*] 2/6 Packing the lab payload + cloud-init seed ..."
tar czf lab.tgz -C "$REPO" webapp provision
base64 < lab.tgz | sed 's/^/      /' > lab.b64

cat > meta-data <<EOF
instance-id: ${VMNAME}-build
local-hostname: progress
EOF

cat > build-inside.sh <<'INSIDE'
#!/bin/bash
mkdir -p /opt/lab
tar xzf /root/lab.tgz -C /opt/lab
{
  if LAB_FUSION=1 USER_FLAG="__USER_FLAG__" ROOT_FLAG="__ROOT_FLAG__" bash /opt/lab/provision/provision.sh; then
    cloud-init clean --logs || true
    rm -f /root/lab.tgz /root/build-inside.sh
    echo "LAB-BUILD-OK"
  else
    echo "LAB-BUILD-FAIL rc=$?"
  fi
} > /dev/console 2>&1
sync
poweroff
INSIDE

# Bake the real flags (from the host env) into the in-VM build script, or leave
# them empty so the provisioner uses its redacted placeholders.
sed -i '' "s|__USER_FLAG__|${USER_FLAG:-}|; s|__ROOT_FLAG__|${ROOT_FLAG:-}|" build-inside.sh

{
  echo "#cloud-config"
  echo "write_files:"
  echo "  - path: /root/lab.tgz"
  echo "    encoding: b64"
  echo "    content: |"
  cat lab.b64
  echo "  - path: /root/build-inside.sh"
  echo "    permissions: '0755'"
  echo "    content: |"
  sed 's/^/      /' build-inside.sh
  echo "runcmd:"
  echo "  - [ bash, /root/build-inside.sh ]"
} > user-data

rm -rf seeddir && mkdir seeddir && cp user-data meta-data seeddir/
rm -f seed.iso
hdiutil makehybrid -quiet -iso -joliet -default-volume-name CIDATA -o seed.iso seeddir

echo "[*] 3/6 Booting arm64 VM (HVF, native) to provision ..."
cp -f "$EDK2_VARS" vars.fd           # writable EFI varstore
chmod u+w vars.fd
rm -f serial.log
qemu-system-aarch64 \
  -machine virt -accel hvf -cpu host -m 2048 -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file="$EDK2_CODE" \
  -drive if=pflash,format=raw,file=vars.fd \
  -drive file=disk.qcow2,if=virtio,format=qcow2 \
  -drive file=seed.iso,if=virtio,format=raw,readonly=on \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -serial file:serial.log -no-reboot 2> qemu.err || true

echo "[*] 4/6 Checking provisioning result ..."
if grep -aq "LAB-BUILD-OK" serial.log; then
  echo "    provisioning OK"
else
  echo "!!! provisioning did NOT report success. Tail of serial log / qemu.err:"
  tail -40 serial.log 2>/dev/null || true
  echo "---- qemu.err ----"; tail -20 qemu.err 2>/dev/null || true
  exit 1
fi

echo "[*] 5/6 Converting disk to VMware VMDK (monolithicFlat — boots in Fusion) ..."
rm -f "${VMNAME}.vmdk" "${VMNAME}-flat.vmdk"
# monolithicFlat writes ${VMNAME}.vmdk (descriptor) + ${VMNAME}-flat.vmdk (data);
# the descriptor already references the -flat extent by this exact name.
qemu-img convert -O vmdk -o subformat=monolithicFlat disk.qcow2 "${VMNAME}.vmdk"

echo "[*] 6/6 Assembling the Fusion VM bundle ..."
BUNDLE="$DIST/${VMNAME}.vmwarevm"
rm -rf "${BUNDLE:?}"; mkdir -p "$BUNDLE"
mv -f "${VMNAME}.vmdk" "${VMNAME}-flat.vmdk" "$BUNDLE/"
cat > "$BUNDLE/${VMNAME}.vmx" <<VMX
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "${VMNAME}"
guestOS = "arm-ubuntu-64"
firmware = "efi"
memsize = "2048"
numvcpus = "2"

pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"

nvme0.present = "TRUE"
nvme0:0.present = "TRUE"
nvme0:0.fileName = "${VMNAME}.vmdk"
nvme0:0.deviceType = "disk"

ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "generated"

usb_xhci.present = "TRUE"
svga.present = "TRUE"
tools.syncTime = "TRUE"
uuid.action = "create"
msg.autoAnswer = "TRUE"
VMX

echo "[+] Done: $BUNDLE"
ls -lh "$BUNDLE"
