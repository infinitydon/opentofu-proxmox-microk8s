#!/usr/bin/env bash
set -euo pipefail

kubernetes_minor="${1:-v1.35}"
helm_key_fingerprint='DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6'

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root on a control-plane node." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gpg
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${kubernetes_minor}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%s/deb/ /\n' \
  "$kubernetes_minor" > /etc/apt/sources.list.d/kubernetes.list

helm_key_tmp="$(mktemp)"
trap 'rm -f "$helm_key_tmp"' EXIT
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey > "$helm_key_tmp"
actual_fingerprint="$(gpg --show-keys --with-colons "$helm_key_tmp" | awk -F: '$1 == "fpr" {print $10; exit}')"
if [[ "$actual_fingerprint" != "$helm_key_fingerprint" ]]; then
  echo "Unexpected Helm repository key fingerprint: $actual_fingerprint" >&2
  exit 1
fi
gpg --dearmor --yes -o /usr/share/keyrings/helm.gpg "$helm_key_tmp"
echo 'deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main' \
  > /etc/apt/sources.list.d/helm-stable-debian.list

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y kubectl helm
install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.kube
microk8s config > /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 0600 /home/ubuntu/.kube/config
runuser -u ubuntu -- kubectl get nodes >/dev/null
runuser -u ubuntu -- helm list --all-namespaces >/dev/null
