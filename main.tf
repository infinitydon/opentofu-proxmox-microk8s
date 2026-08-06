locals {
  control_planes = {
    for i in range(var.control_plane_count) : format("microk8s-cp-%02d", i + 1) => {
      index = i
    }
  }

  workers = {
    for i in range(var.worker_count) : format("microk8s-worker-%02d", i + 1) => {
      index = i
    }
  }
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
  tags      = ["microk8s", "worker", "opentofu"]

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.node_name
    datastore_id = var.storage
    full         = true
    retries      = 3
  }

  cpu {
    cores = var.worker_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.worker_memory_mb
    floating  = var.worker_memory_mb
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = var.worker_disk_gb
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
    queues = var.worker_cpu_cores
  }

  dynamic "network_device" {
    for_each = range(var.worker_data_nic_count)
    content {
      bridge = var.bridge
      model  = "virtio"
      queues = var.worker_cpu_cores
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
