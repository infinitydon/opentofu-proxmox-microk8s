#!/usr/bin/env bash
set -euo pipefail

kubernetes_minor="${1:-v1.35}"
k9s_version="${2:-v0.50.18}"
helm_key_fingerprint='DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6'

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root on a control-plane node." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https bash-completion ca-certificates curl gpg
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
install -d -m 0755 /etc/bash_completion.d
kubectl completion bash > /etc/bash_completion.d/kubectl
chmod 0644 /etc/bash_completion.d/kubectl

deb_arch="$(dpkg --print-architecture)"
case "$deb_arch" in
  amd64|arm64|arm) k9s_arch="$deb_arch" ;;
  *) echo "Unsupported k9s Debian architecture: $deb_arch" >&2; exit 1 ;;
esac
k9s_base_url="https://github.com/derailed/k9s/releases/download/${k9s_version}"
k9s_deb="k9s_linux_${k9s_arch}.deb"
k9s_tmpdir="$(mktemp -d)"
trap 'rm -f "$k9s_tmpdir/$k9s_deb" "$k9s_tmpdir/checksums.sha256" "$helm_key_tmp"; rmdir "$k9s_tmpdir" 2>/dev/null || true' EXIT
curl -fsSL "${k9s_base_url}/${k9s_deb}" -o "${k9s_tmpdir}/${k9s_deb}"
curl -fsSL "${k9s_base_url}/checksums.sha256" -o "${k9s_tmpdir}/checksums.sha256"
(
  cd "$k9s_tmpdir"
  grep -E "[[:space:]]${k9s_deb}$" checksums.sha256 | sha256sum --check --strict -
)
DEBIAN_FRONTEND=noninteractive apt-get install -y "${k9s_tmpdir}/${k9s_deb}"
install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.kube
microk8s config > /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 0600 /home/ubuntu/.kube/config
runuser -u ubuntu -- kubectl get nodes >/dev/null
runuser -u ubuntu -- helm list --all-namespaces >/dev/null
runuser -u ubuntu -- k9s version | grep -F "$k9s_version" >/dev/null
test -s /etc/bash_completion.d/kubectl
