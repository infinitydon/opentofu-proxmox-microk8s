#!/usr/bin/env bash
set -euo pipefail

enable_hostpath="${1:-true}"
enable_multus="${2:-true}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root on a control-plane node." >&2
  exit 1
fi

if [[ "$enable_hostpath" == true ]]; then
  microk8s enable hostpath-storage
else
  microk8s disable hostpath-storage || true
fi

if [[ "$enable_multus" == true ]]; then
  microk8s enable community
  microk8s enable multus
else
  microk8s disable multus || true
fi
