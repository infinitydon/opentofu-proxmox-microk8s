# OpenTofu Proxmox MicroK8s module

Reusable OpenTofu module that creates flexible MicroK8s control-plane and worker
VMs on Proxmox VE. Workers can have additional VirtIO NICs, selected guest NICs
bound persistently to `vfio-pci`, and independently configurable 1 GiB and 2 MiB
hugepage pools.

The current default MicroK8s channel is `1.35/stable`; override
`microk8s_channel` in the calling root module when another channel is required.

```hcl
module "microk8s" {
  source = "git::https://github.com/infinitydon/opentofu-proxmox-microk8s.git?ref=v1.0.0"

  node_name           = "pve"
  template_vm_id      = 9006
  storage             = "ebenezer-stor1"
  control_plane_count = 1
  worker_count        = 2
  first_vm_id         = 170
  cpu_cores           = 4
  memory_mb           = 8192
  disk_gb             = 50
  management_ipv4_prefix = "192.168.88."
}
```

Provider configuration, credentials, remote-state backend, and deployment-specific
values belong in the calling root module. The `scripts` directory contains
idempotent guest bootstrap helpers for MicroK8s, worker VFIO/hugepages/DPDK, addons,
and upstream `kubectl` plus Helm on control-plane nodes.

When both hugepage sizes are enabled, 1 GiB pages are reserved at kernel boot and
2 MiB pages are allocated later by sysctl. This ordering protects the contiguous
memory required by the 1 GiB pool.
