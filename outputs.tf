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
        if contains(local.workers[name].vfio_nic_indexes, i)
      ]
      pool_name    = local.workers[name].pool_name
      cpu_cores    = local.workers[name].cpu_cores
      memory_mb    = local.workers[name].memory_mb
      disk_gb      = local.workers[name].disk_gb
      storage      = local.workers[name].storage
      bridge       = local.workers[name].bridge
      hugepages_1g = local.workers[name].hugepages_1g
      hugepages_2m = local.workers[name].hugepages_2m
      node_labels  = local.worker_node_labels[name]
    }
  }
}

output "cluster_options" {
  value = {
    microk8s_channel        = var.microk8s_channel
    enable_hostpath_storage = var.enable_hostpath_storage
    enable_multus           = var.enable_multus
    multus_version          = var.multus_version
    multus_memory_request   = var.multus_memory_request
    multus_memory_limit     = var.multus_memory_limit
    k9s_version             = var.k9s_version
    kubectl_version         = var.kubectl_version
    helm_version            = var.helm_version
    worker_pools            = local.effective_worker_pools
  }
}

output "cluster_ready" {
  description = "True only after enabled OpenTofu guest automation and health gates complete."
  value       = var.automation_enabled ? true : null
  depends_on  = [terraform_data.cluster_health]
}

output "worker_node_labels" {
  description = "Kubernetes labels requested for every worker node."
  value       = local.worker_node_labels
}
