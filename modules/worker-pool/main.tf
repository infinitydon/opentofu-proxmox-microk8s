locals {
  nodes = {
    for index in range(var.count_nodes) :
    format("%s-%02d", var.name_prefix, index + 1) => index
  }
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
    content {
      bridge = var.bridge
      model  = "virtio"
      queues = var.cpu_cores
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
