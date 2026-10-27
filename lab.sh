#!/bin/bash
# Helper for the Uploadry lab VM.  Usage: ./lab.sh {up|down|reset|shell|status}
set -euo pipefail
cd "$(dirname "$0")"
VM=uploadry
YAML=./lima/uploadry.yaml
RENDERED=./.lima-uploadry.rendered.yaml

# Render the VM definition with this checkout's absolute path (Lima mounts
# need an absolute location; we keep the committed YAML host-agnostic).
render() { sed "s#__LAB_REPO__#$PWD#g" "$YAML" > "$RENDERED"; }

case "${1:-}" in
  up)     if limactl list -q 2>/dev/null | grep -qx "$VM"; then
            limactl start "$VM" --tty=false      # existing instance
          else
            render; limactl start --name="$VM" "$RENDERED" --tty=false   # first create
          fi ;;
  down)   limactl stop "$VM" ;;
  shell)  limactl shell "$VM" ;;
  status) limactl list "$VM" ;;
  reset)  # wipe and rebuild from scratch
          limactl stop "$VM" 2>/dev/null || true
          limactl delete "$VM" 2>/dev/null || true
          render; limactl start --name="$VM" "$RENDERED" --tty=false ;;
  reprovision)  # re-run only the provisioning (keeps the VM)
          limactl shell "$VM" sudo bash /opt/lab/provision/provision.sh ;;
  *) echo "usage: $0 {up|down|reset|reprovision|shell|status}"; exit 1 ;;
esac
