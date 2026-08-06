#!/usr/bin/env bash
set -euo pipefail

channel="${1:-1.35/stable}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-guest-utils qemu-guest-agent jq pciutils
systemctl enable --now qemu-guest-agent

# Kubelet/cAdvisor and CNI agents consume inotify instances. Cloud images can
# inherit limits low enough for kubelite to fail with inotify_init: EMFILE.
cat > /etc/sysctl.d/99-kubernetes-inotify.conf <<'EOF'
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 1048576
EOF
sysctl --system >/dev/null

# Proxmox expands the virtual disk; grow the Ubuntu root partition and
# filesystem so the requested module disk size is usable inside the guest.
root_source="$(findmnt -n -o SOURCE /)"
root_type="$(findmnt -n -o FSTYPE /)"
root_parent="$(lsblk -no PKNAME "$root_source" 2>/dev/null || true)"
root_partnum="$(lsblk -no PARTN "$root_source" 2>/dev/null || true)"
if [[ -n "$root_parent" && -n "$root_partnum" ]]; then
  growpart "/dev/$root_parent" "$root_partnum" || true
fi
case "$root_type" in
  ext2|ext3|ext4) resize2fs "$root_source" ;;
  xfs) xfs_growfs / ;;
esac

if snap list microk8s >/dev/null 2>&1; then
  snap refresh microk8s --channel="$channel"
else
  snap install microk8s --classic --channel="$channel"
fi

usermod -aG microk8s ubuntu
mkdir -p /home/ubuntu/.kube
chown -R ubuntu:ubuntu /home/ubuntu/.kube
systemctl reset-failed 'snap.microk8s.*' 2>/dev/null || true
microk8s start
microk8s status --wait-ready --timeout 600
