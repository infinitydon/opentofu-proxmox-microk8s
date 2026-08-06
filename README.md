# OpenTofu Proxmox MicroK8s

A composable OpenTofu module for creating a production-oriented MicroK8s cluster on Proxmox.

## Architecture

- `modules/control-plane` owns only control-plane VM lifecycle.
- `modules/worker-pool` owns one homogeneous, independently scalable worker pool.
- `modules/cluster-automation` owns MicroK8s installation, joins, labels, add-ons, tools, reboots, and health gates.
- The repository root composes these modules into one supported cluster interface.

No worker sizing or networking inputs exist outside `worker_pools`. Each pool is therefore self-contained and can use different compute, storage, bridges, NIC counts, VFIO assignments, hugepages, and Kubernetes labels.

## Complete invocation

```hcl
module "microk8s" {
  source = "git::https://github.com/infinitydon/opentofu-proxmox-microk8s.git?ref=v5.0.0"

  node_name      = "pve"
  template_vm_id = 9006

  control_plane = {
    count       = 1
    name_prefix = "microk8s-cp"
    cpu_cores   = 4
    memory_mb   = 8192
    disk_gb     = 50
    storage     = "ebenezer-stor1"
    bridge      = "vmbr0"
  }

  worker_pools = {
    dpdk = {
      count                 = 2
      name_prefix           = "microk8s-dpdk"
      cpu_cores             = 4
      memory_mb             = 8192
      disk_gb               = 50
      storage               = "ebenezer-stor1"
      bridge                = "vmbr0"
      data_nic_count        = 4
      vfio_nic_indexes      = [0, 1]
      hugepages_1g          = 2
      hugepages_2m          = 1024
      os_reserved_memory_mb = 2048
      node_labels = {
        "osvbng.infinitydon.com/bng-frr-ha" = "true"
        "dpdk-enabled"                      = "true"
      }
    }

    general = {
      count                 = 2
      name_prefix           = "microk8s-general"
      cpu_cores             = 4
      memory_mb             = 8192
      disk_gb               = 50
      storage               = "ebenezer-stor1"
      bridge                = "vmbr0"
      data_nic_count        = 0
      vfio_nic_indexes      = []
      hugepages_1g          = 0
      hugepages_2m          = 0
      os_reserved_memory_mb = 2048
      node_labels           = { "workload-type" = "general" }
    }
  }

  kubernetes = {
    microk8s_channel = "1.35/stable"
    kubectl_version   = "1.35.7"
    helm_version      = "3.21.3"
    k9s_version       = "v0.50.18"
  }

  addons = {
    hostpath_storage = true
    multus = {
      enabled        = true
      version        = "v4.3.0"
      memory_request = "256Mi"
      memory_limit   = "512Mi"
    }
  }

  automation = {
    enabled     = true
    ssh_user    = "ubuntu"
    ssh_port    = 22
    revision    = "1"
    reboot_wait = "75s"
  }

  guest_ssh_private_key_path = var.guest_ssh_private_key_path
}
```

## Control-plane quorum

`control_plane.count` must be a positive odd number: `1`, `3`, `5`, and so on. Three or five nodes provide datastore quorum; one node is supported for compact deployments but has no failure quorum. Secondary control-plane nodes are joined to the primary before workers are admitted.

## Worker-pool behavior

The root adds `opentofu.infinitydon.com/worker-pool=<pool-name>` to every worker. User labels are supplied as a `map(string)`, preventing malformed unquoted `key=value` list entries. An empty map adds no user labels.

The worker-pool submodule is also independently addressable at `//modules/worker-pool`, but direct callers are responsible for cluster joining; the supported root module coordinates joins and cluster-wide health.

## Completion semantics

`cluster_ready=true` is returned only after all named nodes are Ready, requested labels are reconciled, hostpath storage and upstream Multus thick plugin are rolled out, a Multus smoke pod succeeds, and pinned kubectl, Helm, k9s, and shell completion are verified.
