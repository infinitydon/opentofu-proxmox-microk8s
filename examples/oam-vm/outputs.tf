output "oam" {
  value = {
    vm_id     = proxmox_virtual_environment_vm.oam.vm_id
    name      = proxmox_virtual_environment_vm.oam.name
    ipv4      = split("/", var.oam_ipv4)[0]
    cpu_cores = var.cpu_cores
    memory_mb = var.memory_mb
    disk_gb   = var.disk_gb
    storage   = var.storage
  }
}
