variable "node_name" {
  description = "Proxmox node that hosts all cluster VMs."
  type        = string
  default     = "pve"
}

variable "template_vm_id" {
  description = "Proxmox Ubuntu cloud-image template VM ID."
  type        = number
  default     = 9006
}

variable "control_plane" {
  description = "Complete control-plane topology and VM configuration. Count must be a positive odd number for quorum."
  type = object({
    count       = number
    name_prefix = string
    cpu_cores   = number
    memory_mb   = number
    disk_gb     = number
    storage     = string
    bridge      = string
  })

  validation {
    condition = (
      var.control_plane.count >= 1 &&
      var.control_plane.count % 2 == 1 &&
      var.control_plane.cpu_cores > 0 &&
      var.control_plane.memory_mb > 0 &&
      var.control_plane.disk_gb > 0 &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.control_plane.name_prefix))
    )
    error_message = "control_plane.count must be a positive odd number (1, 3, 5, ...), with positive resources and a DNS-safe name_prefix."
  }
}

variable "worker_pools" {
  description = "Named, independently scalable worker pools. Every pool declares its complete VM, networking, VFIO, hugepage, and label configuration."
  type = map(object({
    count                 = number
    name_prefix           = string
    cpu_cores             = number
    memory_mb             = number
    disk_gb               = number
    storage               = string
    bridge                = string
    data_nic_count        = number
    vfio_nic_indexes      = set(number)
    hugepages_1g          = number
    hugepages_2m          = number
    os_reserved_memory_mb = number
    node_labels           = map(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, pool in var.worker_pools :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name)) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", pool.name_prefix)) &&
      pool.count >= 0 && pool.cpu_cores > 0 && pool.memory_mb > 0 && pool.disk_gb > 0 &&
      pool.data_nic_count >= 0 && pool.hugepages_1g >= 0 && pool.hugepages_2m >= 0 &&
      pool.os_reserved_memory_mb >= 0 && pool.os_reserved_memory_mb <= pool.memory_mb &&
      pool.hugepages_1g * 1024 + pool.hugepages_2m * 2 <= pool.memory_mb - pool.os_reserved_memory_mb &&
      alltrue([for index in pool.vfio_nic_indexes : index >= 0 && index < pool.data_nic_count]) &&
      alltrue([for key, value in pool.node_labels :
        can(regex("^[A-Za-z0-9]([A-Za-z0-9._/-]*[A-Za-z0-9])?$", key)) &&
        !strcontains(key, "=") && !strcontains(value, "=")
      ])
    ])
    error_message = "Each worker pool must have valid names/resources; VFIO indexes must address data NICs; hugepages must fit after reserved memory; labels must be valid key/value entries."
  }
}

variable "kubernetes" {
  description = "Pinned Kubernetes and control-plane client tool versions."
  type = object({
    microk8s_channel = string
    kubectl_version  = string
    helm_version     = string
    k9s_version      = string
  })

  validation {
    condition = (
      can(regex("^[0-9]+\\.[0-9]+/(stable|candidate|beta|edge)$", var.kubernetes.microk8s_channel)) &&
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes.kubectl_version)) &&
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes.helm_version)) &&
      can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes.k9s_version))
    )
    error_message = "kubernetes versions must use a MicroK8s channel and exact kubectl, Helm, and k9s semantic versions."
  }
}

variable "addons" {
  description = "Cluster-wide add-ons installed once from the primary control plane."
  type = object({
    hostpath_storage = bool
    multus = object({
      enabled        = bool
      version        = string
      memory_request = string
      memory_limit   = string
    })
  })
}

variable "automation" {
  description = "Guest and cluster automation behavior."
  type = object({
    enabled     = bool
    ssh_user    = string
    ssh_port    = number
    revision    = string
    reboot_wait = string
  })
}

variable "guest_ssh_private_key_path" {
  description = "Absolute path on the OpenTofu runner to the guest SSH private key."
  type        = string
  default     = null
  nullable    = true
}
