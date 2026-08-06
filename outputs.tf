output "control_planes" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.control_plane : name => {
      vm_id = vm.vm_id
      management_ipv4 = one(vm.ipv4_addresses[index(
        [for mac in vm.mac_addresses : lower(mac)],
        lower(vm.network_device[0].mac_address)
      )])
      management_mac = vm.network_device[0].mac_address
    }
  }
}

output "workers" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.worker : name => {
      vm_id = vm.vm_id
      management_ipv4 = one(vm.ipv4_addresses[index(
        [for mac in vm.mac_addresses : lower(mac)],
        lower(vm.network_device[0].mac_address)
      )])
      management_mac = vm.network_device[0].mac_address
      data_macs      = local.worker_data_macs[name]
      vfio_macs = [
        for i, mac in local.worker_data_macs[name] : mac
        if contains(var.worker_vfio_nic_indexes, i)
      ]
      node_labels = var.worker_node_labels
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
    multus_version          = var.multus_version
    multus_memory_request   = var.multus_memory_request
    multus_memory_limit     = var.multus_memory_limit
    worker_node_labels      = var.worker_node_labels
  }
}

output "cluster_ready" {
  description = "True only after enabled OpenTofu guest automation and health gates complete."
  value       = var.automation_enabled ? true : null
  depends_on  = [terraform_data.cluster_health]
}

output "worker_node_labels" {
  description = "Kubernetes labels requested for every worker node."
  value       = var.worker_node_labels
}
