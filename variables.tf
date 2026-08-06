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
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "first_vm_id" {
  type    = number
  default = 170
}

variable "cpu_cores" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_gb" {
  type    = number
  default = 50
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "management_ipv4_prefix" {
  description = "Prefix used to select the management IPv4 address reported by the guest agent."
  type        = string
  default     = "192.168.88."
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

variable "microk8s_channel" {
  type    = string
  default = "1.35/stable"
}
