module "microk8s" {
  source = "git::https://github.com/infinitydon/opentofu-proxmox-microk8s.git?ref=v5.0.5"

  node_name      = var.node_name
  template_vm_id = var.template_vm_id
  control_plane  = var.control_plane
  worker_pools   = var.worker_pools
  kubernetes     = var.kubernetes
  addons         = var.addons

  automation = {
    enabled     = false
    ssh_user    = "ubuntu"
    ssh_port    = 22
    revision    = "ansible-owned"
    reboot_wait = "0s"
  }
}
