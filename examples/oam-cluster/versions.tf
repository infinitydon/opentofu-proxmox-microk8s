terraform {
  required_version = ">= 1.10"
  backend "pg" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }
}
