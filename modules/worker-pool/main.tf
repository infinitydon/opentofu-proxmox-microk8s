locals {
  nodes = {
    for index in range(var.count_nodes) :
    format("%s-%02d", var.name_prefix, index + 1) => index
  }

  data_nics = {
    for pair in setproduct(keys(local.nodes), range(var.data_nic_count)) :
    "${pair[0]}/${pair[1]}" => {
      node_name = pair[0]
      index     = pair[1]
    }
  }
}

resource "random_id" "data_nic_mac" {
  for_each = local.data_nics

  byte_length = 5
}

resource "proxmox_virtual_environment_vm" "this" {
  for_each = local.nodes

  name      = each.key
  node_name = var.node_name
  machine   = "q35,viommu=intel"
  tags      = ["microk8s", "worker", "opentofu", "pool-${var.pool_name}"]

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.node_name
    datastore_id = var.storage
    full         = true
    retries      = 3
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
    floating  = var.memory_mb
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = var.disk_gb
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
    queues = var.cpu_cores
  }

  dynamic "network_device" {
    for_each = range(var.data_nic_count)
    iterator = data_nic
    content {
      bridge      = var.bridge
      model       = "virtio"
      queues      = var.cpu_cores
      mac_address = join(":", concat(["02"], regexall("..", random_id.data_nic_mac["${each.key}/${data_nic.value}"].hex)))
    }
  }

  initialization {
    datastore_id = var.storage
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  agent { enabled = true }
  started         = true
  stop_on_destroy = true
}
