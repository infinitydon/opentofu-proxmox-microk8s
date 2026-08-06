variable "control_planes" { type = any }
variable "workers" { type = any }
variable "worker_node_labels" { type = map(list(string)) }
variable "guest_ssh_private_key_path" { type = string }
variable "kubernetes" {
  type = object({ microk8s_channel = string, kubectl_version = string, helm_version = string, k9s_version = string })
}
variable "addons" {
  type = object({ hostpath_storage = bool, multus = object({ enabled = bool, version = string, memory_request = string, memory_limit = string }) })
}
variable "automation" {
  type = object({ enabled = bool, ssh_user = string, ssh_port = number, revision = string, reboot_wait = string })
}
