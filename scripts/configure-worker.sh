#!/usr/bin/env bash
set -euo pipefail

pages_1g="${1:?1 GiB page count required}"
pages_2m="${2:?2 MiB page count required}"
all_data_macs_csv="${3:?all data NIC MACs required}"
vfio_macs_csv="${4:?VFIO NIC MACs required}"

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

if (( pages_1g * 1024 + pages_2m * 2 > 6144 )); then
  echo "Hugepages may not exceed 6 GiB on an 8 GiB worker." >&2
  exit 1
fi

if (( pages_1g > 0 )) && ! grep -qw pdpe1gb /proc/cpuinfo; then
  echo "The guest CPU does not expose 1 GiB page support." >&2
  exit 1
fi

IFS=',' read -r -a all_data_macs <<< "$all_data_macs_csv"
IFS=',' read -r -a vfio_macs <<< "$vfio_macs_csv"

netplan=/etc/netplan/60-worker-data-nics.yaml
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
netplan generate
netplan apply

modprobe vfio
modprobe vfio-pci
printf '%s\n' vfio vfio-pci > /etc/modules-load.d/worker-vfio.conf

vfio_bdf_file=/etc/worker-vfio-pci.list
: > "$vfio_bdf_file"
for wanted_mac in "${vfio_macs[@]}"; do
  interface=''
  for address_file in /sys/class/net/*/address; do
    if [[ "$(<"$address_file")" == "${wanted_mac,,}" ]]; then
      interface="$(basename "$(dirname "$address_file")")"
      break
    fi
  done
  if [[ -z "$interface" || "$interface" == "eth0" ]]; then
    echo "Refusing VFIO mapping for $wanted_mac: interface missing or management eth0." >&2
    exit 1
  fi
  # A VirtIO net interface resolves to .../<PCI-BDF>/virtioN; its parent is
  # the PCI function that must be bound to vfio-pci.
  bdf="$(basename "$(dirname "$(readlink -f "/sys/class/net/$interface/device")")")"
  printf '%s # %s %s\n' "$bdf" "$interface" "$wanted_mac" >> "$vfio_bdf_file"
done

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

install -m 0755 /tmp/verify-worker-config /usr/local/sbin/verify-worker-config
install -m 0644 /tmp/worker-config-verify.service /etc/systemd/system/worker-config-verify.service
printf 'PAGES_1G=%d\nPAGES_2M=%d\n' "$pages_1g" "$pages_2m" > /etc/worker-hugepages.conf
systemctl daemon-reload
systemctl enable worker-config-verify.service

echo "Worker configuration staged; reboot required."
