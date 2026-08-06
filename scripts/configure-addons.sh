#!/usr/bin/env bash
set -euo pipefail

enable_hostpath="${1:-true}"
enable_multus="${2:-true}"
multus_version="${3:-v4.3.0}"
multus_memory_request="${4:-256Mi}"
multus_memory_limit="${5:-512Mi}"

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
  manifest_url="https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/${multus_version}/deployments/multus-daemonset-thick.yml"
  manifest="$(mktemp)"
  trap 'rm -f "$manifest"' EXIT

  curl -fsSL "$manifest_url" \
    | sed \
        -e "s|ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick|ghcr.io/k8snetworkplumbingwg/multus-cni:${multus_version}-thick|g" \
        -e '/"chrootDir": "\/hostroot",/a\        "binDir": "/var/snap/microk8s/current/opt/cni/bin",' \
        -e 's|path: /etc/cni/net.d$|path: /var/snap/microk8s/current/args/cni-network/|' \
        -e 's|path: /opt/cni/bin$|path: /var/snap/microk8s/current/opt/cni/bin/|' \
    > "$manifest"

  microk8s kubectl apply -f "$manifest"
  microk8s kubectl patch daemonset kube-multus-ds -n kube-system --type=strategic \
    -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"kube-multus\",\"resources\":{\"requests\":{\"cpu\":\"100m\",\"memory\":\"${multus_memory_request}\"},\"limits\":{\"cpu\":\"100m\",\"memory\":\"${multus_memory_limit}\"}}}]}}}}"
  # Remove pods from the previous template immediately. This also recovers upgrades
  # where an old thick-plugin pod cannot cleanly terminate after its CNI path moves.
  microk8s kubectl delete pods -n kube-system -l app=multus \
    --force --grace-period=0 --ignore-not-found --wait=false
  microk8s kubectl rollout status daemonset/kube-multus-ds -n kube-system --timeout=300s
else
  microk8s kubectl delete daemonset kube-multus-ds -n kube-system --ignore-not-found
fi
