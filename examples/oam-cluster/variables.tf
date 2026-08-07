variable "proxmox_endpoint" {
  type    = string
  default = "https://192.168.88.2:8006/"
}
variable "proxmox_api_token" {
  type      = string
  sensitive = true
}
variable "proxmox_insecure" {
  type    = bool
  default = true
}
variable "node_name" {
  type    = string
  default = "pve"
}
variable "template_vm_id" {
  type    = number
  default = 9006
}

variable "control_plane" {
  type = object({
    count   = number, name_prefix = string, cpu_cores = number, memory_mb = number,
    disk_gb = number, storage = string, bridge = string
  })
  default = {
    count   = 3, name_prefix = "microk8s-cp", cpu_cores = 4, memory_mb = 8192,
    disk_gb = 50, storage = "ebenezer-stor1", bridge = "vmbr0"
  }
}

variable "worker_pools" {
  type = map(object({
    count                 = number, name_prefix = string, cpu_cores = number, memory_mb = number,
    disk_gb               = number, storage = string, bridge = string, data_nic_count = number,
    vfio_nic_indexes      = set(number), hugepages_1g = number, hugepages_2m = number,
    os_reserved_memory_mb = number, node_labels = map(string)
  }))
  default = {
    dpdk = {
      count                 = 2, name_prefix = "microk8s-dpdk", cpu_cores = 4, memory_mb = 8192,
      disk_gb               = 50, storage = "ebenezer-stor1", bridge = "vmbr0", data_nic_count = 4,
      vfio_nic_indexes      = [0, 1], hugepages_1g = 2, hugepages_2m = 1024,
      os_reserved_memory_mb = 2048,
      node_labels           = { "dpdk-enabled" = "true", "osvbng.infinitydon.com/bng-frr-ha" = "true" }
    }
    general = {
      count                 = 1, name_prefix = "microk8s-general", cpu_cores = 4, memory_mb = 8192,
      disk_gb               = 50, storage = "ebenezer-stor1", bridge = "vmbr0", data_nic_count = 4,
      vfio_nic_indexes      = [], hugepages_1g = 0, hugepages_2m = 0,
      os_reserved_memory_mb = 2048, node_labels = { "workload-type" = "general" }
    }
  }
}

variable "kubernetes" {
  type    = object({ microk8s_channel = string, kubectl_version = string, helm_version = string, k9s_version = string })
  default = { microk8s_channel = "1.35/stable", kubectl_version = "1.35.7", helm_version = "3.21.3", k9s_version = "v0.50.18" }
}

variable "addons" {
  type = object({
    hostpath_storage = bool
    multus           = object({ enabled = bool, version = string, memory_request = string, memory_limit = string })
  })
  default = {
    hostpath_storage = true
    multus           = { enabled = true, version = "v4.3.0", memory_request = "256Mi", memory_limit = "512Mi" }
  }
}
