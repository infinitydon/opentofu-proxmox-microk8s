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

variable "storage" {
  type    = string
  default = "ebenezer-stor1"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "oam_ipv4" {
  type    = string
  default = "192.168.88.4/24"
}

variable "oam_gateway" {
  type    = string
  default = "192.168.88.1"
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 4096
}

variable "disk_gb" {
  type    = number
  default = 50
}
