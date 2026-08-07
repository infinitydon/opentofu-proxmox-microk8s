#!/usr/bin/env bash
set -euo pipefail

node_name="${1:?worker node name required}"
labels_json_b64="${2:?base64-encoded labels JSON required}"
state_dir=/var/lib/opentofu-worker-labels
state_file="${state_dir}/${node_name}.keys"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root on a control-plane node." >&2
  exit 1
fi

labels_json="$(printf '%s' "$labels_json_b64" | base64 --decode)" || {
  echo "Worker labels payload is not valid base64." >&2
  exit 1
}
if ! jq -e 'type == "array" and all(.[]; type == "string")' \
  <<< "$labels_json" >/dev/null; then
  echo "Worker labels payload is not a valid JSON string array." >&2
  exit 1
fi
mapfile -t labels < <(jq -r '.[]' <<< "$labels_json")
declare -A wanted_keys=()

# A successful `microk8s join` returns before the Node object is guaranteed to
# be visible through the API server. Do not race label reconciliation against
# kubelet registration.
node_ready=false
for _ in {1..120}; do
  if [[ "$(microk8s kubectl get node "$node_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)" == "True" ]]; then
    node_ready=true
    break
  fi
  sleep 5
done
if [[ "$node_ready" != true ]]; then
  echo "Worker ${node_name} did not register as Ready within 10 minutes." >&2
  microk8s kubectl get nodes -o wide >&2 || true
  exit 1
fi

for label in "${labels[@]}"; do
  key="${label%%=*}"
  wanted_keys["$key"]=1
done

if [[ -f "$state_file" ]]; then
  while IFS= read -r old_key; do
    [[ -z "$old_key" || -n "${wanted_keys[$old_key]:-}" ]] && continue
    microk8s kubectl label node "$node_name" "${old_key}-" >/dev/null
  done < "$state_file"
fi

if (( ${#labels[@]} > 0 )); then
  microk8s kubectl label node "$node_name" "${labels[@]}" --overwrite >/dev/null
  node_json="$(microk8s kubectl get node "$node_name" -o json)"
  for label in "${labels[@]}"; do
    key="${label%%=*}"
    value="${label#*=}"
    jq -e --arg key "$key" --arg value "$value" \
      '.metadata.labels[$key] == $value' <<< "$node_json" >/dev/null
  done
fi

install -d -m 0755 "$state_dir"
printf '%s\n' "${!wanted_keys[@]}" | sed '/^$/d' | sort > "$state_file"

if (( ${#labels[@]} == 0 )); then
  echo "No module-managed labels configured for ${node_name}"
else
  echo "Worker labels reconciled on ${node_name}: ${labels[*]}"
fi
