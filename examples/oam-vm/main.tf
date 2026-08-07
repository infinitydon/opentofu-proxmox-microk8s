resource "proxmox_virtual_environment_vm" "oam" {
  name      = "microk8s-oam"
  node_name = var.node_name
  tags      = ["oam", "opentofu", "ansible", "microk8s"]

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
  }

  initialization {
    datastore_id = var.storage
    dns {
      servers = ["192.168.88.1", "1.1.1.1"]
    }
    ip_config {
      ipv4 {
        address = var.oam_ipv4
        gateway = var.oam_gateway
      }
    }
  }

  agent { enabled = true }
  started         = true
  stop_on_destroy = true
}
