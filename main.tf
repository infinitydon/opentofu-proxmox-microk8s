module "control_plane" {
  source = "./modules/control-plane"

  node_name      = var.node_name
  template_vm_id = var.template_vm_id
  count_nodes    = var.control_plane.count
  name_prefix    = var.control_plane.name_prefix
  cpu_cores      = var.control_plane.cpu_cores
  memory_mb      = var.control_plane.memory_mb
  disk_gb        = var.control_plane.disk_gb
  storage        = var.control_plane.storage
  bridge         = var.control_plane.bridge
}

module "worker_pool" {
  for_each = var.worker_pools
  source   = "./modules/worker-pool"

  node_name             = var.node_name
  template_vm_id        = var.template_vm_id
  pool_name             = each.key
  name_prefix           = each.value.name_prefix
  count_nodes           = each.value.count
  cpu_cores             = each.value.cpu_cores
  memory_mb             = each.value.memory_mb
  disk_gb               = each.value.disk_gb
  storage               = each.value.storage
  bridge                = each.value.bridge
  data_nic_count        = each.value.data_nic_count
  vfio_nic_indexes      = each.value.vfio_nic_indexes
  hugepages_1g          = each.value.hugepages_1g
  hugepages_2m          = each.value.hugepages_2m
  os_reserved_memory_mb = each.value.os_reserved_memory_mb
  node_labels = merge(each.value.node_labels, {
    "opentofu.infinitydon.com/worker-pool" = each.key
  })
}

locals {
  control_planes = module.control_plane.nodes
  workers        = merge([for pool in module.worker_pool : pool.nodes]...)

  worker_node_labels = {
    for name, worker in local.workers : name => [
      for key in sort(keys(worker.node_labels)) : "${key}=${worker.node_labels[key]}"
    ]
  }

}

module "cluster_automation" {
  source = "./modules/cluster-automation"

  control_planes             = local.control_planes
  workers                    = local.workers
  worker_node_labels         = local.worker_node_labels
  kubernetes                 = var.kubernetes
  addons                     = var.addons
  automation                 = var.automation
  guest_ssh_private_key_path = var.guest_ssh_private_key_path
}
