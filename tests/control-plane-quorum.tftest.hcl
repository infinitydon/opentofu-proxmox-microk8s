mock_provider "proxmox" {}
mock_provider "random" {}
mock_provider "time" {}

variables {
  node_name      = "pve"
  template_vm_id = 9006
  worker_pools   = {}
  kubernetes = {
    microk8s_channel = "1.35/stable"
    kubectl_version  = "1.35.7"
    helm_version     = "3.21.3"
    k9s_version      = "v0.50.18"
  }
  addons = {
    hostpath_storage = false
    multus = {
      enabled        = false
      version        = "v4.3.0"
      memory_request = "256Mi"
      memory_limit   = "512Mi"
    }
  }
  automation = {
    enabled     = false
    ssh_user    = "ubuntu"
    ssh_port    = 22
    revision    = "test"
    reboot_wait = "1s"
  }
  guest_ssh_private_key_path = null
}

run "one_control_plane" {
  command = plan
  variables {
    control_plane = {
      count   = 1, name_prefix = "cp", cpu_cores = 2, memory_mb = 4096,
      disk_gb = 20, storage = "local", bridge = "vmbr0"
    }
  }
}

run "three_control_planes" {
  command = plan
  variables {
    control_plane = {
      count   = 3, name_prefix = "cp", cpu_cores = 2, memory_mb = 4096,
      disk_gb = 20, storage = "local", bridge = "vmbr0"
    }
  }
}

run "five_control_planes" {
  command = plan
  variables {
    control_plane = {
      count   = 5, name_prefix = "cp", cpu_cores = 2, memory_mb = 4096,
      disk_gb = 20, storage = "local", bridge = "vmbr0"
    }
  }
}

run "reject_even_control_plane_count" {
  command = plan
  variables {
    control_plane = {
      count   = 2, name_prefix = "cp", cpu_cores = 2, memory_mb = 4096,
      disk_gb = 20, storage = "local", bridge = "vmbr0"
    }
  }
  expect_failures = [var.control_plane]
}
