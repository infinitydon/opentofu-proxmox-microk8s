#!/usr/bin/env bash
set -euo pipefail

vm_id="${VM_ID:-169}"
vm_name="${VM_NAME:-opentofu-state-postgres}"
template_id="${TEMPLATE_ID:-9006}"
storage="${STORAGE:-ebenezer-stor1}"

if qm status "$vm_id" >/dev/null 2>&1; then
  echo "VM ${vm_id} already exists; refusing to overwrite it." >&2
  exit 1
fi

case "$storage" in
  ebenezer-stor1|eben-stor-2) ;;
  *) echo "STORAGE must be ebenezer-stor1 or eben-stor-2." >&2; exit 1 ;;
esac

qm clone "$template_id" "$vm_id" --name "$vm_name" --full 1 --storage "$storage"
qm set "$vm_id" --cores 2
qm set "$vm_id" --memory 2048
qm set "$vm_id" --balloon 1024
qm set "$vm_id" --ipconfig0 ip=192.168.88.3/24,gw=192.168.88.1
qm set "$vm_id" --nameserver 192.168.88.1
qm set "$vm_id" --description PostgreSQL-remote-state-backend-for-OpenTofu
qm resize "$vm_id" scsi0 64G
qm start "$vm_id"

qm config "$vm_id"
