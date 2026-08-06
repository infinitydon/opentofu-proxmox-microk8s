#!/usr/bin/env bash
set -euo pipefail

expected_nodes="${1:?expected node count required}"
expected_names_csv="${2:?expected node names required}"
microk8s_minor="${3:?MicroK8s minor version required}"
enable_hostpath="${4:?hostpath option required}"
enable_multus="${5:?Multus option required}"
multus_version="${6:?Multus version required}"
multus_memory_request="${7:?Multus memory request required}"
multus_memory_limit="${8:?Multus memory limit required}"
control_plane_ipv4="${9:?control-plane IPv4 address required}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root on the primary control-plane node." >&2
  exit 1
fi

# Address changes are explicit recovery operations. Never rotate certificates
# from a routine OpenTofu health check.
if ! openssl x509 -in /var/snap/microk8s/current/certs/server.crt \
  -noout -checkip "$control_plane_ipv4" >/dev/null 2>&1; then
  echo "The MicroK8s API certificate does not contain ${control_plane_ipv4}; refusing automatic certificate rotation." >&2
  exit 1
fi

install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.kube
microk8s config > /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 0600 /home/ubuntu/.kube/config

kctl=(runuser -u ubuntu -- kubectl)
helmctl=(runuser -u ubuntu -- helm)

"${kctl[@]}" wait nodes --all --for=condition=Ready --timeout=600s
actual_nodes="$("${kctl[@]}" get nodes --no-headers | wc -l)"
[[ "$actual_nodes" -eq "$expected_nodes" ]] || {
  echo "Expected ${expected_nodes} nodes, found ${actual_nodes}." >&2
  exit 1
}

IFS=',' read -r -a expected_names <<< "$expected_names_csv"
for node in "${expected_names[@]}"; do
  "${kctl[@]}" get node "$node" >/dev/null
  version="$("${kctl[@]}" get node "$node" -o jsonpath='{.status.nodeInfo.kubeletVersion}')"
  [[ "$version" == "v${microk8s_minor}."* ]] || {
    echo "$node runs $version, expected v${microk8s_minor}.x." >&2
    exit 1
  }
done

"${kctl[@]}" version --client >/dev/null
"${helmctl[@]}" version >/dev/null
"${helmctl[@]}" list --all-namespaces >/dev/null

if [[ "$enable_hostpath" == true ]]; then
  "${kctl[@]}" get storageclass microk8s-hostpath >/dev/null
  "${kctl[@]}" rollout status deployment/hostpath-provisioner \
    -n kube-system --timeout=300s
fi

if [[ "$enable_multus" == true ]]; then
  "${kctl[@]}" rollout status daemonset/kube-multus-ds \
    -n kube-system --timeout=600s
  image="$("${kctl[@]}" get daemonset kube-multus-ds -n kube-system \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="kube-multus")].image}')"
  request="$("${kctl[@]}" get daemonset kube-multus-ds -n kube-system \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="kube-multus")].resources.requests.memory}')"
  limit="$("${kctl[@]}" get daemonset kube-multus-ds -n kube-system \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="kube-multus")].resources.limits.memory}')"
  [[ "$image" == "ghcr.io/k8snetworkplumbingwg/multus-cni:${multus_version}-thick" ]]
  [[ "$request" == "$multus_memory_request" ]]
  [[ "$limit" == "$multus_memory_limit" ]]

  smoke_namespace="opentofu-multus-smoke"
  "${kctl[@]}" delete namespace "$smoke_namespace" --ignore-not-found --wait=true
  trap '"${kctl[@]}" delete namespace "$smoke_namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT
  "${kctl[@]}" create namespace "$smoke_namespace"
  "${kctl[@]}" apply -n "$smoke_namespace" -f - <<'EOF'
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: smoke-secondary
spec:
  config: '{"cniVersion":"0.3.1","type":"ptp","ipam":{"type":"host-local","subnet":"10.254.254.0/24"}}'
---
apiVersion: v1
kind: Pod
metadata:
  name: multus-smoke
  annotations:
    k8s.v1.cni.cncf.io/networks: smoke-secondary
spec:
  restartPolicy: Never
  containers:
    - name: pause
      image: registry.k8s.io/pause:3.10
EOF
  "${kctl[@]}" wait pod/multus-smoke -n "$smoke_namespace" \
    --for=condition=Ready --timeout=300s
  network_status="$("${kctl[@]}" get pod multus-smoke -n "$smoke_namespace" \
    -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}')"
  grep -q 'smoke-secondary' <<< "$network_status"
  "${kctl[@]}" delete namespace "$smoke_namespace" --wait=true
  trap - EXIT
fi

echo "OpenTofu cluster health gate passed."
