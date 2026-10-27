#!/bin/bash
# =====================================================================
# build-x86-ova.sh — build the Uploadry target as an x86_64 VM and
# export it as an OVA, uploadable to VulnHub / TryHackMe / HTB review.
#
# Runs on Apple Silicon using QEMU TCG (x86 emulation — slow but works).
# Reuses provision/provision.sh unchanged via cloud-init.
#
#   ./build/build-x86-ova.sh
#
# Output: dist/uploadry.ova
# =====================================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ART="${ART_DIR:-${TMPDIR:-/tmp}/uploadry-build/ova}"
DIST="$REPO/dist"
IMG_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
DISK_GB=10
NAME=uploadry

mkdir -p "$ART" "$DIST"
cd "$ART"

echo "[*] 1/7 Fetching Ubuntu 22.04 amd64 cloud image ..."
[ -f base.img ] || curl -fL --retry 3 -o base.img "$IMG_URL"
cp -f base.img disk.qcow2
qemu-img resize disk.qcow2 "${DISK_GB}G"

echo "[*] 2/7 Packing the lab payload ..."
tar czf lab.tgz -C "$REPO" webapp provision
base64 < lab.tgz | sed 's/^/      /' > lab.b64   # 6-space indent for YAML (BSD base64: read stdin)

echo "[*] 3/7 Writing cloud-init seed ..."
cat > meta-data <<EOF
instance-id: ${NAME}-build
local-hostname: ${NAME}
EOF

cat > build-inside.sh <<'INSIDE'
#!/bin/bash
mkdir -p /opt/lab
tar xzf /root/lab.tgz -C /opt/lab
{
  if bash /opt/lab/provision/provision.sh; then
    # provision.sh already writes /home/michael/user.txt and /root/root.txt
    # clean cloud-init so the image boots fresh on the target platform
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

# Build the seed ISO from a dir holding ONLY the two cloud-init files,
# so the image stays tiny (never include the multi-GB disks).
rm -rf seeddir && mkdir seeddir && cp user-data meta-data seeddir/
rm -f seed.iso
hdiutil makehybrid -quiet -iso -joliet -default-volume-name CIDATA -o seed.iso seeddir

echo "[*] 4/7 Booting emulated x86 VM to provision (this is slow under TCG) ..."
rm -f serial.log
qemu-system-x86_64 \
  -machine q35 -accel tcg -cpu max -m 2048 -smp 2 \
  -drive file=disk.qcow2,if=virtio,format=qcow2 \
  -drive file=seed.iso,if=virtio,format=raw,readonly=on \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -serial file:serial.log -no-reboot 2> qemu.err || true

echo "[*] 5/7 Checking provisioning result ..."
if grep -q "LAB-BUILD-OK" serial.log; then
  echo "    provisioning OK"
else
  echo "!!! provisioning did NOT report success. Tail of serial log:"
  tail -40 serial.log || true
  exit 1
fi

echo "[*] 6/7 Converting disk to stream-optimized VMDK ..."
qemu-img convert -O vmdk -o subformat=streamOptimized disk.qcow2 "${NAME}-disk.vmdk"
VMDK="${NAME}-disk.vmdk"
VMDK_SIZE=$(stat -f%z "$VMDK")
CAP=$(( DISK_GB * 1024 * 1024 * 1024 ))

echo "[*] 7/7 Writing OVF and packaging OVA ..."
cat > "${NAME}.ovf" <<OVF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="${VMDK}" ovf:id="file1" ovf:size="${VMDK_SIZE}"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="${CAP}" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="NAT">
      <Description>NAT network</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="${NAME}">
    <Info>Uploadry - deliberately vulnerable lab target</Info>
    <Name>${NAME}</Name>
    <OperatingSystemSection ovf:id="94" ovf:version="22.04">
      <Info>Ubuntu 22.04 (64-bit)</Info>
      <Description>Ubuntu_64</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemType>virtualbox-2.2</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Caption>1 virtual CPU</rasd:Caption>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:ElementName>1 virtual CPU</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>1</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
        <rasd:Caption>512 MB of memory</rasd:Caption>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>512 MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>512</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Caption>sataController0</rasd:Caption>
        <rasd:Description>SATA Controller</rasd:Description>
        <rasd:ElementName>sataController0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>AHCI</rasd:ResourceSubType>
        <rasd:ResourceType>20</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Caption>disk1</rasd:Caption>
        <rasd:Description>Disk Image</rasd:Description>
        <rasd:ElementName>disk1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Caption>Ethernet adapter on 'NAT'</rasd:Caption>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:ElementName>Ethernet adapter on 'NAT'</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
OVF

rm -f "$DIST/${NAME}.ova"
COPYFILE_DISABLE=1 tar -cf "$DIST/${NAME}.ova" -C "$ART" "${NAME}.ovf" "${VMDK}"

echo "[+] Done: $DIST/${NAME}.ova"
ls -lh "$DIST/${NAME}.ova"
