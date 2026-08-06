locals {
  control_planes = {
    for i in range(var.control_plane_count) : format("microk8s-cp-%02d", i + 1) => {
      index = i
      vm_id = var.first_vm_id + i
      mac   = format("02:10:00:00:%02x:00", i + 1)
    }
  }

  workers = {
    for i in range(var.worker_count) : format("microk8s-worker-%02d", i + 1) => {
      index = i
      vm_id = var.first_vm_id + var.control_plane_count + i
      mac   = format("02:20:00:00:%02x:00", i + 1)
      data_macs = [
        for nic in range(var.worker_data_nic_count) :
        format("02:20:%02x:%02x:%02x:01", i + 1, nic + 1, nic + 1)
      ]
    }
  }
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  for_each = local.control_planes

  name      = each.key
  vm_id     = each.value.vm_id
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
    bridge      = var.bridge
    model       = "virtio"
    mac_address = each.value.mac
    queues      = var.cpu_cores
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
  vm_id     = each.value.vm_id
  node_name = var.node_name
  machine   = "q35,viommu=intel"
  tags      = ["microk8s", "worker", "opentofu"]

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
    bridge      = var.bridge
    model       = "virtio"
    mac_address = each.value.mac
    queues      = var.cpu_cores
  }

  dynamic "network_device" {
    for_each = each.value.data_macs
    content {
      bridge      = var.bridge
      model       = "virtio"
      mac_address = network_device.value
      queues      = var.cpu_cores
    }
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
