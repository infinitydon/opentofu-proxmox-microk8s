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
      data_macs = [
        for index in range(var.data_nic_count) :
        join(":", concat(["02"], regexall("..", random_id.data_nic_mac["${name}/${index}"].hex)))
      ]
      pool_name             = var.pool_name
      cpu_cores             = var.cpu_cores
      memory_mb             = var.memory_mb
      disk_gb               = var.disk_gb
      storage               = var.storage
      bridge                = var.bridge
      data_nic_count        = var.data_nic_count
      vfio_nic_indexes      = var.vfio_nic_indexes
      hugepages_1g          = var.hugepages_1g
      hugepages_2m          = var.hugepages_2m
      os_reserved_memory_mb = var.os_reserved_memory_mb
      node_labels           = var.node_labels
    }
  }
}
