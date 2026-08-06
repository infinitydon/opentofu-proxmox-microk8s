#!/usr/bin/env bash
set -euo pipefail

pages_1g="${1:?1 GiB page count required}"
pages_2m="${2:?2 MiB page count required}"
all_data_macs_csv="${3-}"
vfio_macs_csv="${4-}"
max_hugepage_mb="${5:-6144}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y dpdk
devbind_source="$(dpkg -L dpdk | grep -E '/dpdk-devbind.py$' | head -n 1)"
if [[ -z "$devbind_source" ]]; then
  echo "dpdk-devbind.py was not supplied by the dpdk package." >&2
  exit 1
fi
ln -sfn "$devbind_source" /usr/local/sbin/dpdk-devbind.py
/usr/local/sbin/dpdk-devbind.py --status >/dev/null

if (( pages_1g * 1024 + pages_2m * 2 > max_hugepage_mb )); then
  echo "Hugepages may not exceed ${max_hugepage_mb} MiB on this worker." >&2
  exit 1
fi

current_1g="$(< /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages)"
reboot_required=false
if [[ -f /var/run/reboot-required ]]; then
  reboot_required=true
fi
if [[ "$current_1g" -ne "$pages_1g" ]]; then
  reboot_required=true
fi

if (( pages_1g > 0 )) && ! grep -qw pdpe1gb /proc/cpuinfo; then
  echo "The guest CPU does not expose 1 GiB page support." >&2
  exit 1
fi

all_data_macs=()
vfio_macs=()
[[ -z "$all_data_macs_csv" ]] || IFS=',' read -r -a all_data_macs <<< "$all_data_macs_csv"
[[ -z "$vfio_macs_csv" ]] || IFS=',' read -r -a vfio_macs <<< "$vfio_macs_csv"

netplan=/etc/netplan/60-worker-data-nics.yaml
if (( ${#all_data_macs[@]} > 0 )); then
  {
    echo 'network:'
    echo '  version: 2'
    echo '  ethernets:'
    for i in "${!all_data_macs[@]}"; do
      printf '    data%d:\n' "$i"
      echo '      match:'
      printf '        macaddress: "%s"\n' "${all_data_macs[$i]}"
      echo '      dhcp4: false'
      echo '      dhcp6: false'
      echo '      link-local: []'
      echo '      optional: true'
    done
  } > "$netplan"
  chmod 0600 "$netplan"
else
  rm -f "$netplan"
fi
netplan generate
netplan apply

modprobe vfio
modprobe vfio-pci
printf '%s\n' vfio vfio-pci > /etc/modules-load.d/worker-vfio.conf

vfio_bdf_file=/etc/worker-vfio-pci.list
vfio_bdf_file_new="$(mktemp)"
trap 'rm -f "$vfio_bdf_file_new"' EXIT
declare -A previous_vfio_bdfs=()
if [[ -f "$vfio_bdf_file" ]]; then
  while read -r saved_bdf _saved_hash _saved_interface saved_mac; do
    if [[ -n "${saved_bdf:-}" && -n "${saved_mac:-}" ]]; then
      previous_vfio_bdfs["${saved_mac,,}"]="$saved_bdf"
    fi
  done < "$vfio_bdf_file"
fi
mapfile -t bound_vfio_bdfs < <(
  find /sys/bus/pci/drivers/vfio-pci -mindepth 1 -maxdepth 1 -type l \
    -printf '%f\n' 2>/dev/null | grep -E '^[0-9a-fA-F]{4}:' | sort
)
vfio_index=0
for wanted_mac in "${vfio_macs[@]}"; do
  interface=''
  for address_file in /sys/class/net/*/address; do
    if [[ "$(<"$address_file")" == "${wanted_mac,,}" ]]; then
      interface="$(basename "$(dirname "$address_file")")"
      break
    fi
  done
  if [[ -z "$interface" && -n "${previous_vfio_bdfs[${wanted_mac,,}]:-}" ]]; then
    bdf="${previous_vfio_bdfs[${wanted_mac,,}]}"
    interface="vfio-bound"
  elif [[ -z "$interface" && ${#bound_vfio_bdfs[@]} -eq ${#vfio_macs[@]} ]]; then
    bdf="${bound_vfio_bdfs[$vfio_index]}"
    interface="vfio-bound"
  elif [[ -z "$interface" || "$interface" == "eth0" ]]; then
    echo "Refusing VFIO mapping for $wanted_mac: interface missing or management eth0." >&2
    exit 1
  else
    # A VirtIO net interface resolves to .../<PCI-BDF>/virtioN; its parent is
    # the PCI function that must be bound to vfio-pci.
    bdf="$(basename "$(dirname "$(readlink -f "/sys/class/net/$interface/device")")")"
  fi
  printf '%s # %s %s\n' "$bdf" "$interface" "$wanted_mac" >> "$vfio_bdf_file_new"
  ((vfio_index += 1))
done
install -m 0644 "$vfio_bdf_file_new" "$vfio_bdf_file"

install -m 0755 /tmp/bind-worker-vfio /usr/local/sbin/bind-worker-vfio
install -m 0644 /tmp/worker-vfio-bind.service /etc/systemd/system/worker-vfio-bind.service
systemctl daemon-reload
systemctl enable worker-vfio-bind.service

if (( pages_1g > 0 )); then
  printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT hugepagesz=1G hugepages=%d"\n' \
    "$pages_1g" > /etc/default/grub.d/60-worker-1g-hugepages.cfg
else
  rm -f /etc/default/grub.d/60-worker-1g-hugepages.cfg
fi
update-grub

printf '# Allocate 2 MiB pages after boot-time 1 GiB pages.\nvm.nr_hugepages=%d\n' \
  "$pages_2m" > /etc/sysctl.d/60-worker-2m-hugepages.conf
sysctl -p /etc/sysctl.d/60-worker-2m-hugepages.conf

install -m 0755 /tmp/verify-worker-config /usr/local/sbin/verify-worker-config
install -m 0644 /tmp/worker-config-verify.service /etc/systemd/system/worker-config-verify.service
printf 'PAGES_1G=%d\nPAGES_2M=%d\n' "$pages_1g" "$pages_2m" > /etc/worker-hugepages.conf
systemctl daemon-reload
systemctl enable worker-config-verify.service

if [[ "$reboot_required" == true ]]; then
  touch /var/lib/opentofu-worker-reboot-required
  echo "Worker configuration staged; reboot required."
else
  rm -f /var/lib/opentofu-worker-reboot-required
  systemctl restart worker-vfio-bind.service
  systemctl restart worker-config-verify.service
  echo "Worker configuration applied without a reboot."
fi
