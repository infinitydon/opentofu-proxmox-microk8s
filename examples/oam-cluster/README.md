# OpenTofu + Ansible MicroK8s deployment

This project runs unchanged from the Ubuntu OAM VM. OpenTofu owns only Proxmox
VM, disk, CPU, memory, and NIC lifecycle. Ansible owns guest configuration,
MicroK8s membership, VFIO, hugepages, add-ons, tools, reboots, and health checks.

The project is located at `/home/ubuntu/opentofu-ansible-microk8s` on the OAM
VM. No Windows path or PowerShell script is used by the deployment workflow.

## Required environment

Store secrets outside Git in `~/.config/microk8s-oam/environment`:

```bash
export PG_CONN_STR='<postgresql-connection-string>'
export PG_SCHEMA_NAME='microk8s_cluster'
export TF_VAR_proxmox_api_token='<user@realm!token=secret>'
```

The Ubuntu guest key is `~/.ssh/prox_vm_key` with mode `0600`.

## Operations

```bash
source ~/.config/microk8s-oam/environment
make init
make plan
make infra
make configure
```

Or run the complete workflow:

```bash
source ~/.config/microk8s-oam/environment
make deploy
```

`make infra` examines the saved plan before applying it. Workers removed from a
pool leave MicroK8s and have their Kubernetes Node objects deleted before
OpenTofu deletes their VMs.

Proxmox mutations default to `TOFU_PARALLELISM=1` because concurrent clones and
raw-disk expansions on the same storage can time out or race on cloud-init
volumes. Override it only when the selected storage is known to support safe
parallel mutations, for example `make TOFU_PARALLELISM=2 deploy`.

To destroy a cluster safely:

```bash
make destroy
```

`make destroy` removes cluster members cleanly with Ansible and then runs the
OpenTofu destruction non-interactively. The OAM VM has separate state and is
not affected by cluster destruction.

During deployment, Ansible checks Ubuntu's `/var/run/reboot-required` marker on
every node. Control planes reboot one at a time to preserve quorum; workers
reboot when either Ubuntu or their hugepage/VFIO configuration requires it.
The final health gate is not reached until required reboots have completed.
The workflow also re-establishes SSH after cloud-init finishes, covering package
updates that restart the Ubuntu SSH service during the initial boot.

## Responsibility boundary

OpenTofu plans contain only Proxmox infrastructure and stable MAC allocations.
Ansible output contains named configuration and verification tasks. The remote
module is invoked with `automation.enabled = false`, so none of its legacy
`remote-exec` resources are created.

The dynamic inventory reads `tofu output -json`; no management addresses or MAC
addresses are hardcoded. Worker pool membership, data NIC MACs, VFIO selection,
hugepages, and labels are passed to Ansible as host variables.

## Control-plane quorum

Set `control_plane.count` to an odd value: `1`, `3`, or `5`. Additional control
planes are joined serially to the stable primary (`<name_prefix>-01`). kubectl,
shell completion, Helm, and k9s are installed and verified on every control
plane. Cluster-wide add-ons and the final health gate run once from the primary.

When reducing the count, `scripts/pre-apply.py` detects departing control-plane
VMs in the saved plan. Ansible makes each one leave MicroK8s and removes its Node
through a surviving control plane before OpenTofu deletes the VM. Removing every
control plane is rejected; use `make destroy` for complete teardown.

## Recovery

The PostgreSQL state backend remains on `192.168.88.3`. If OAM is rebuilt,
restore the environment file and SSH key, copy or clone this project, and run:

```bash
source ~/.config/microk8s-oam/environment
tofu init
make inventory
make configure
```

OpenTofu reconnects to the existing remote state and Ansible reconciles the
existing nodes idempotently.
