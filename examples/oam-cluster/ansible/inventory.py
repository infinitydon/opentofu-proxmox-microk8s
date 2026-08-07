#!/usr/bin/env python3
import json
import subprocess


def tofu_outputs():
    raw = subprocess.check_output(["tofu", "output", "-json"], cwd="..", text=True)
    return {key: item["value"] for key, item in json.loads(raw).items()}


def main():
    outputs = tofu_outputs()
    hostvars = {}
    control_planes = sorted(outputs["control_planes"])
    workers = sorted(outputs["workers"])

    for name, node in outputs["control_planes"].items():
        hostvars[name] = {
            "ansible_host": node["management_ipv4"],
            "ansible_user": "ubuntu",
            "ansible_ssh_private_key_file": "~/.ssh/prox_vm_key",
            "node_role": "control_plane",
        }

    pool_groups = {}
    for name, node in outputs["workers"].items():
        hostvars[name] = {
            "ansible_host": node["management_ipv4"],
            "ansible_user": "ubuntu",
            "ansible_ssh_private_key_file": "~/.ssh/prox_vm_key",
            "node_role": "worker",
            "worker_pool": node["pool_name"],
            "memory_mb": node["memory_mb"],
            "data_macs": node["data_macs"],
            "vfio_macs": node["vfio_macs"],
            "hugepages_1g": node["hugepages_1g"],
            "hugepages_2m": node["hugepages_2m"],
            "os_reserved_memory_mb": node["os_reserved_memory_mb"],
            "node_labels": node["node_labels"],
        }
        pool_groups.setdefault("pool_" + node["pool_name"], []).append(name)

    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {"children": ["control_planes", "workers"] + sorted(pool_groups)},
        "control_planes": {"hosts": control_planes},
        "primary_control_plane": {"hosts": control_planes[:1]},
        "secondary_control_planes": {"hosts": control_planes[1:]},
        "workers": {"hosts": workers},
    }
    inventory.update({group: {"hosts": sorted(hosts)} for group, hosts in pool_groups.items()})
    print(json.dumps(inventory))


if __name__ == "__main__":
    main()
