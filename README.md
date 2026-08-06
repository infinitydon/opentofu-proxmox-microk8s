# OpenTofu Proxmox MicroK8s module

Reusable OpenTofu module that creates MicroK8s control-plane and worker VMs on
Proxmox VE. Proxmox allocates VM IDs. Management addresses are resolved by matching
the configured management NIC MAC against QEMU guest-agent data, so no subnet is
hardcoded or required.

Control-plane and worker resources are independently configurable. Workers can
have additional VirtIO NICs, selected guest NICs persistently bound to `vfio-pci`,
and independently configurable 1 GiB and 2 MiB hugepage pools.

## Complete root invocation

This example deliberately shows every module input. Provider configuration,
credentials, and the remote-state backend belong in the calling root module.

```hcl
module "microk8s" {
  source = "git::https://github.com/infinitydon/opentofu-proxmox-microk8s.git?ref=v2.0.0"

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

  worker_data_nic_count   = 4
  worker_vfio_nic_indexes = [0, 1]

  hugepages_1g = 2
  hugepages_2m = 1024

  enable_hostpath_storage = true
  enable_multus           = true
  microk8s_channel        = "1.35/stable"
}
```

The `scripts` directory contains idempotent helpers for MicroK8s, worker
VFIO/hugepages/DPDK, addons, and upstream `kubectl` plus Helm on control-plane
nodes. When both hugepage sizes are enabled, 1 GiB pages are reserved at kernel
boot and 2 MiB pages are allocated afterward by sysctl.
