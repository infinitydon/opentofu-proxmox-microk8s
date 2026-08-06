# OpenTofu Proxmox MicroK8s module

Reusable OpenTofu module that creates MicroK8s control-plane and worker VMs on
Proxmox VE. Proxmox allocates both VM IDs and NIC MAC addresses. Management
addresses are read from the first NIC's QEMU guest-agent data, so no subnet or MAC
address is hardcoded or required.

Control-plane and worker resources are independently configurable. Workers can
have additional VirtIO NICs, selected guest NICs persistently bound to `vfio-pci`,
and independently configurable 1 GiB and 2 MiB hugepage pools.

## Complete root invocation

This example deliberately shows every module input. Provider configuration,
credentials, and the remote-state backend belong in the calling root module.

```hcl
module "microk8s" {
  source = "git::https://github.com/infinitydon/opentofu-proxmox-microk8s.git?ref=v4.0.0"

  node_name      = "pve"
  template_vm_id = 9006
  storage        = "ebenezer-stor1"
  bridge         = "vmbr0"

  control_plane_count     = 1
  control_plane_cpu_cores = 4
  control_plane_memory_mb = 8192
  control_plane_disk_gb   = 50

  worker_count        = 2
  worker_cpu_cores    = 4
  worker_memory_mb    = 8192
  worker_disk_gb      = 50
  worker_os_reserved_memory_mb = 2048

  worker_data_nic_count   = 4
  worker_vfio_nic_indexes = [0, 1]
  worker_node_labels = [
  ]

  worker_pools = {
    dpdk = {
      count                 = 2
      cpu_cores             = 4
      memory_mb             = 8192
      disk_gb               = 40
      storage               = "ebenezer-stor1"
      bridge                = "vmbr0"
      data_nic_count        = 4
      vfio_nic_indexes      = [0, 1]
      hugepages_1g          = 2
      hugepages_2m          = 1024
      os_reserved_memory_mb = 2048
      node_labels = [
        "osvbng.infinitydon.com/bng-frr-ha=true",
        "dpdk-enabled=true",
      ]
    }
    general = {
      count                 = 2
      cpu_cores             = 4
      memory_mb             = 8192
      disk_gb               = 40
      storage               = "ebenezer-stor1"
      bridge                = "vmbr0"
      data_nic_count        = 0
      vfio_nic_indexes      = []
      hugepages_1g          = 0
      hugepages_2m          = 0
      os_reserved_memory_mb = 2048
      node_labels           = ["workload-type=general"]
    }
  }

  hugepages_1g = 2
  hugepages_2m = 1024

  enable_hostpath_storage = true
  enable_multus           = true
  multus_version          = "v4.3.0"
  multus_memory_request   = "256Mi"
  multus_memory_limit     = "512Mi"
  microk8s_channel        = "1.35/stable"
  k9s_version             = "v0.50.18"
  kubectl_version         = "1.35.7"
  helm_version            = "3.21.3"

  automation_enabled           = true
  guest_ssh_user                = "ubuntu"
  guest_ssh_private_key_path    = "/absolute/path/to/vm_private_key"
  guest_ssh_port                = 22
  automation_revision           = "1"
  worker_reboot_wait            = "75s" # post-reboot SSH wait for every node
}
```

The `scripts` directory contains idempotent helpers for MicroK8s, worker
VFIO/hugepages/DPDK, addons, and upstream `kubectl` plus Helm on control-plane
nodes. Multus uses the pinned upstream thick-plugin image rather than the MicroK8s
community addon. Its daemon defaults to a 256 MiB request and 512 MiB limit, replacing
the upstream quickstart manifest's 50 MiB values. When both hugepage sizes are enabled, 1 GiB pages are reserved at kernel
boot and 2 MiB pages are allocated afterward by sysctl.

Every control-plane node receives exact pinned `kubectl_version` and
`helm_version` packages, system-wide kubectl Bash completion, and the
checksum-verified pinned `k9s_version` release. kubectl and Helm are held against
unintended APT upgrades. The health gate verifies their exact binary versions as
the normal Ubuntu user, and kubectl's major/minor must match `microk8s_channel`.

`worker_pools` provides ASG-like independently scalable worker groups. Every pool
can override count, CPU, memory, disk, Proxmox storage/bridge, additional NICs,
VFIO indexes, both hugepage sizes, reserved OS memory, and node labels. All pools
join the same control plane. Named pools automatically receive
`opentofu.infinitydon.com/worker-pool=<pool>`. When `worker_pools = {}`, the
legacy `worker_*`, hugepage, and shared-label inputs synthesize the original
`microk8s-worker-NN` default pool.

`worker_node_labels` applies the same list of Kubernetes `key=value` labels to
every worker. Its default is `[]`, which adds no labels. Labels previously managed
by the module are reconciled, so removing an entry removes that label without
touching labels managed elsewhere.

Verbose installer output is retained on each node under
`/tmp/opentofu-*.log`. Normal applies show concise phase completion and health-gate
results; if a phase fails, its last 80 log lines are printed automatically.
The `terraform_data` resources expose structured `input` fields so a plan shows
the intended label reconciliation and health checks. OpenTofu cannot introspect
individual commands inside a shell provisioner.
Script fingerprints remain necessary to rerun automation when implementation
changes, but operational resources use named trigger objects such as
`script_sha256` rather than anonymous positional hash values.

Changing only `worker_node_labels` reruns label reconciliation and verification;
it does not rerun the full cluster health gate. The health gate runs on initial
creation and when one of its Kubernetes/addon/tool inputs, implementation hash, or
`automation_revision` changes.

Ubuntu Noble cloud-init may return exit code 2 for a completed run containing
recoverable warnings. Automation accepts that code only when the final status is
exactly `done`, prints the concise recoverable-warning section, and continues.
Fatal, incomplete, or error states still fail the apply.

## Automated success criteria

With `automation_enabled = true` (the default), a successful apply means more than
VM creation. OpenTofu waits for guest SSH, installs MicroK8s, configures worker
VFIO/DPDK/hugepages, conditionally reboots nodes, joins all nodes, installs addons
and control-plane tools, and then runs blocking health gates.

The final gate verifies expected node names/count, Ready state, selected Kubernetes
minor version, hostpath storage when enabled, pinned Multus thick images and memory,
normal-user kubectl/Helm access, and a temporary Multus secondary-network pod. Each
worker separately verifies persistent VFIO bindings, exact hugepage counts,
`dpdk-devbind.py`, and that MicroK8s runs with its control plane disabled.

`cluster_ready` is emitted only after those gates pass. Any failed command fails the
OpenTofu apply. This is deployment-time convergence, not continuous monitoring;
Prometheus or another monitoring system should handle ongoing health after apply.

The first control-plane address is recorded as part of installation. A later address
change fails the apply with an explicit drift error; routine automation never edits
dqlite addresses, worker proxy endpoints, kubeconfigs, or MicroK8s certificates.
Restore the original DHCP lease or perform a deliberate MicroK8s address migration.
Normal lease renewal with the same address requires no reservation or special action.

The private-key path is evaluated on the machine running OpenTofu. The key contents
are not a module input, avoiding storage of the private key in OpenTofu state.
