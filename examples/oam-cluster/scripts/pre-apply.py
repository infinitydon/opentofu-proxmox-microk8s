#!/usr/bin/env python3
import json
import subprocess
import sys


def output(command, cwd=None):
    return json.loads(subprocess.check_output(command, cwd=cwd, text=True))


plan_file = sys.argv[1] if len(sys.argv) > 1 else "cluster.tfplan"
current = output(["tofu", "output", "-json"])
planned = output(["tofu", "show", "-json", plan_file])
current_workers = set(current.get("workers", {}).get("value") or {})
current_control_planes = set(current.get("control_planes", {}).get("value") or {})
removed_workers = sorted({
    change.get("change", {}).get("before", {}).get("name")
    for change in planned.get("resource_changes", [])
    if "delete" in change.get("change", {}).get("actions", [])
    and ".module.worker_pool[" in change.get("address", "")
    and change.get("change", {}).get("before", {}).get("name") in current_workers
})
removed_control_planes = sorted({
    change.get("change", {}).get("before", {}).get("name")
    for change in planned.get("resource_changes", [])
    if "delete" in change.get("change", {}).get("actions", [])
    and ".module.control_plane." in change.get("address", "")
    and change.get("change", {}).get("before", {}).get("name") in current_control_planes
})
surviving_control_planes = sorted(current_control_planes - set(removed_control_planes))

if removed_control_planes and not surviving_control_planes:
    raise SystemExit(
        "The plan removes every control plane. Use 'make destroy' for a complete cluster teardown."
    )

if removed_workers or removed_control_planes:
    if removed_workers:
        print("Draining and removing workers before Proxmox deletion: " + ", ".join(removed_workers))
    if removed_control_planes:
        print("Leaving and removing control planes before Proxmox deletion: " + ", ".join(removed_control_planes))
    subprocess.run(
        [
            "ansible-playbook",
            "playbooks/scale-down.yml",
            "--extra-vars",
            json.dumps({
                "removed_workers": removed_workers,
                "removed_control_planes": removed_control_planes,
                "control_plane_coordinator": surviving_control_planes[0],
            }),
        ],
        cwd="ansible",
        check=True,
    )
else:
    print("No Kubernetes node scale-down actions are required.")
