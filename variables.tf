variable "node_name" {
  type    = string
  default = "pve"
}

variable "template_vm_id" {
  type    = number
  default = 9006
}

variable "storage" {
  type    = string
  default = "ebenezer-stor1"
}

variable "control_plane_count" {
  type    = number
  default = 1

  validation {
    condition     = var.control_plane_count >= 1
    error_message = "At least one control-plane node is required."
  }
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "control_plane_cpu_cores" {
  type    = number
  default = 4
}

variable "control_plane_memory_mb" {
  type    = number
  default = 8192
}

variable "control_plane_disk_gb" {
  type    = number
  default = 50
}

variable "worker_cpu_cores" {
  type    = number
  default = 4
}

variable "worker_memory_mb" {
  type    = number
  default = 8192
}

variable "worker_disk_gb" {
  type    = number
  default = 50
}

variable "worker_os_reserved_memory_mb" {
  description = "Worker memory left outside hugepage pools for Ubuntu and Kubernetes."
  type        = number
  default     = 2048
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "worker_data_nic_count" {
  type    = number
  default = 4
}

variable "worker_vfio_nic_indexes" {
  description = "Zero-based indexes within each worker's additional NIC list."
  type        = set(number)
  default     = [0, 1]

  validation {
    condition     = alltrue([for i in var.worker_vfio_nic_indexes : i >= 0 && i < var.worker_data_nic_count])
    error_message = "Every VFIO NIC index must identify an additional worker NIC."
  }
}

variable "worker_node_labels" {
  description = "Kubernetes labels applied to every worker, expressed as key=value strings. An empty list manages no worker labels."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for label in var.worker_node_labels :
      can(regex("^[^=[:space:]]+=[^=[:space:]]+$", label))
    ])
    error_message = "Each worker_node_labels entry must be a non-empty key=value string containing exactly one equals sign."
  }
}

variable "hugepages_1g" {
  description = "Number of 1 GiB pages reserved at worker boot."
  type        = number
  default     = 2
}

variable "hugepages_2m" {
  description = "Number of 2 MiB pages allocated after the boot-time 1 GiB reservation."
  type        = number
  default     = 1024
}

variable "enable_hostpath_storage" {
  type    = bool
  default = true
}

variable "enable_multus" {
  type    = bool
  default = true
}

variable "multus_version" {
  description = "Pinned upstream Multus CNI release used for the thick-plugin deployment."
  type        = string
  default     = "v4.3.0"
}

variable "multus_memory_request" {
  description = "Memory request for each upstream Multus daemon."
  type        = string
  default     = "256Mi"
}

variable "multus_memory_limit" {
  description = "Memory limit for each upstream Multus daemon."
  type        = string
  default     = "512Mi"
}

variable "microk8s_channel" {
  type    = string
  default = "1.35/stable"
}

variable "k9s_version" {
  description = "Pinned upstream k9s release installed on control-plane nodes."
  type        = string
  default     = "v0.50.18"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.k9s_version))
    error_message = "k9s_version must be a release tag such as v0.50.18."
  }
}

variable "automation_enabled" {
  description = "Run guest configuration, joins, reboots, addons, tools, and health gates from OpenTofu."
  type        = bool
  default     = true
}

variable "guest_ssh_user" {
  description = "Cloud-image user used for guest automation."
  type        = string
  default     = "ubuntu"
}

variable "guest_ssh_private_key_path" {
  description = "Absolute path on the OpenTofu runner to the guest SSH private key. Required when automation is enabled."
  type        = string
  default     = null
  nullable    = true
}

variable "guest_ssh_port" {
  type    = number
  default = 22
}

variable "automation_revision" {
  description = "Bump to intentionally rerun idempotent guest automation after implementation changes."
  type        = string
  default     = "1"
}

variable "worker_reboot_wait" {
  description = "Wait after conditionally scheduling worker reboots."
  type        = string
  default     = "75s"
}
