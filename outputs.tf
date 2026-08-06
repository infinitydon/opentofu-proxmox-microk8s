output "control_planes" {
  description = "Generated control-plane VM identities and management addresses."
  value       = local.control_planes
}

output "workers" {
  description = "Generated worker identities, pool membership, NICs, and effective configuration."
  value = {
    for name, worker in local.workers : name => merge(worker, {
      vfio_macs = [
        for index, mac in worker.data_macs : mac
        if contains(worker.vfio_nic_indexes, index)
      ]
      node_labels = local.worker_node_labels[name]
    })
  }
}

output "cluster_options" {
  value = {
    control_plane = var.control_plane
    worker_pools  = var.worker_pools
    kubernetes    = var.kubernetes
    addons        = var.addons
  }
}

output "cluster_ready" {
  description = "True only after enabled guest automation and health gates complete."
  value       = module.cluster_automation.cluster_ready
}

output "worker_node_labels" {
  description = "Effective Kubernetes labels for each worker node."
  value       = local.worker_node_labels
}
