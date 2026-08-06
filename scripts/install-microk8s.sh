#!/usr/bin/env bash
set -euo pipefail

channel="${1:-1.35/stable}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent jq pciutils
systemctl enable --now qemu-guest-agent

if snap list microk8s >/dev/null 2>&1; then
  snap refresh microk8s --channel="$channel"
else
  snap install microk8s --classic --channel="$channel"
fi

usermod -aG microk8s ubuntu
mkdir -p /home/ubuntu/.kube
chown -R ubuntu:ubuntu /home/ubuntu/.kube
microk8s status --wait-ready --timeout 600
