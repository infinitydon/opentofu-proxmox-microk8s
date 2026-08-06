locals {
  control_planes = {
    for i in range(var.control_plane_count) : format("microk8s-cp-%02d", i + 1) => {
      index = i
    }
  }

  legacy_worker_pool = {
    count                 = var.worker_count
    cpu_cores             = null
    memory_mb             = null
    disk_gb               = null
    storage               = null
    bridge                = null
    data_nic_count        = null
    vfio_nic_indexes      = null
    hugepages_1g          = null
    hugepages_2m          = null
    os_reserved_memory_mb = null
    node_labels           = null
  }

  configured_worker_pools = merge(var.worker_pools, {
    for pool_name in toset(length(var.worker_pools) == 0 ? ["default"] : []) :
    pool_name => local.legacy_worker_pool
  })

  effective_worker_pools = {
    for pool_name, pool in local.configured_worker_pools : pool_name => {
      count                 = pool.count
      cpu_cores             = coalesce(pool.cpu_cores, var.worker_cpu_cores)
      memory_mb             = coalesce(pool.memory_mb, var.worker_memory_mb)
      disk_gb               = coalesce(pool.disk_gb, var.worker_disk_gb)
      storage               = coalesce(pool.storage, var.storage)
      bridge                = coalesce(pool.bridge, var.bridge)
      data_nic_count        = coalesce(pool.data_nic_count, var.worker_data_nic_count)
      vfio_nic_indexes      = coalesce(pool.vfio_nic_indexes, var.worker_vfio_nic_indexes)
      hugepages_1g          = coalesce(pool.hugepages_1g, var.hugepages_1g)
      hugepages_2m          = coalesce(pool.hugepages_2m, var.hugepages_2m)
      os_reserved_memory_mb = coalesce(pool.os_reserved_memory_mb, var.worker_os_reserved_memory_mb)
      node_labels = distinct(concat(
        var.worker_node_labels,
        coalesce(pool.node_labels, []),
        pool_name == "default" ? [] : ["opentofu.infinitydon.com/worker-pool=${pool_name}"],
      ))
    }
  }

  workers = merge([
    for pool_name, pool in local.effective_worker_pools : {
      for i in range(pool.count) :
      format("%s-%02d", pool_name == "default" ? "microk8s-worker" : "microk8s-${pool_name}", i + 1) => merge(pool, {
        index     = i
        pool_name = pool_name
      })
    }
  ]...)
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  for_each = local.control_planes

  name      = each.key
  node_name = var.node_name
  tags      = ["microk8s", "control-plane", "opentofu"]

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.node_name
    datastore_id = var.storage
    full         = true
    retries      = 3
  }

  cpu {
    cores = var.control_plane_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.control_plane_memory_mb
    floating  = var.control_plane_memory_mb
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = var.control_plane_disk_gb
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
    queues = var.control_plane_cpu_cores
  }

  initialization {
    datastore_id = var.storage
    ip_config {
      ipv4 { address = "dhcp" }
    }
  }

  agent { enabled = true }
  started         = true
  stop_on_destroy = true
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = local.workers

  name      = each.key
  node_name = var.node_name
  machine   = "q35,viommu=intel"
  tags      = ["microk8s", "worker", "opentofu", "pool-${each.value.pool_name}"]

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.node_name
    datastore_id = each.value.storage
    full         = true
    retries      = 3
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
    floating  = each.value.memory_mb
  }

  disk {
    datastore_id = each.value.storage
    interface    = "scsi0"
    size         = each.value.disk_gb
  }

  network_device {
    bridge = each.value.bridge
    model  = "virtio"
    queues = each.value.cpu_cores
  }

  dynamic "network_device" {
    for_each = range(each.value.data_nic_count)
    content {
      bridge = each.value.bridge
      model  = "virtio"
      queues = each.value.cpu_cores
    }
  }

  initialization {
    datastore_id = each.value.storage
    ip_config {
      ipv4 { address = "dhcp" }
    }
  }

  agent { enabled = true }
  started         = true
  stop_on_destroy = true
}
