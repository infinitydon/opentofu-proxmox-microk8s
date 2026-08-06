output "nodes" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.this : name => {
      id             = vm.id
      vm_id          = vm.vm_id
      management_mac = try(vm.network_device[0].mac_address, null)
      management_ipv4 = try(one(vm.ipv4_addresses[index(
        [for mac in vm.mac_addresses : lower(mac)],
        lower(vm.network_device[0].mac_address)
      )]), null)
      disk_gb = var.disk_gb
    }
  }
}
