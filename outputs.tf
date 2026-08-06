output "control_planes" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.control_plane : name => {
      vm_id = vm.vm_id
      management_ipv4 = one([
        for address in flatten(vm.ipv4_addresses) : address
        if startswith(address, var.management_ipv4_prefix)
      ])
    }
  }
}

output "workers" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.worker : name => {
      vm_id = vm.vm_id
      management_ipv4 = one([
        for address in flatten(vm.ipv4_addresses) : address
        if startswith(address, var.management_ipv4_prefix)
      ])
      data_macs = local.workers[name].data_macs
      vfio_macs = [
        for i, mac in local.workers[name].data_macs : mac
        if contains(var.worker_vfio_nic_indexes, i)
      ]
    }
  }
}

output "cluster_options" {
  value = {
    microk8s_channel        = var.microk8s_channel
    hugepages_1g            = var.hugepages_1g
    hugepages_2m            = var.hugepages_2m
    enable_hostpath_storage = var.enable_hostpath_storage
    enable_multus           = var.enable_multus
  }
}
