locals {
  primary_control_plane_name = sort(keys(local.control_planes))[0]
  secondary_control_planes = {
    for name, node in local.control_planes : name => node
    if name != local.primary_control_plane_name
  }
  control_plane_ipv4 = {
    for name, vm in proxmox_virtual_environment_vm.control_plane : name => one(
      vm.ipv4_addresses[index(
        [for mac in vm.mac_addresses : lower(mac)],
        lower(vm.network_device[0].mac_address)
      )]
    )
  }
  worker_ipv4 = {
    for name, vm in proxmox_virtual_environment_vm.worker : name => one(
      vm.ipv4_addresses[index(
        [for mac in vm.mac_addresses : lower(mac)],
        lower(vm.network_device[0].mac_address)
      )]
    )
  }
  worker_data_macs = {
    for name, vm in proxmox_virtual_environment_vm.worker : name => [
      for device in slice(vm.network_device, 1, 1 + var.worker_data_nic_count) : device.mac_address
    ]
  }
  primary_control_plane_ipv4 = local.control_plane_ipv4[local.primary_control_plane_name]
  microk8s_minor             = split("/", var.microk8s_channel)[0]
  expected_node_names        = concat(sort(keys(local.control_planes)), sort(keys(local.workers)))
  max_worker_hugepage_mb     = var.worker_memory_mb - var.worker_os_reserved_memory_mb
}

resource "random_password" "control_plane_join_token" {
  for_each = var.automation_enabled ? local.secondary_control_planes : {}

  length  = 32
  special = false
}

resource "random_password" "worker_join_token" {
  for_each = var.automation_enabled ? local.workers : {}

  length  = 32
  special = false
}

resource "terraform_data" "control_plane_install" {
  for_each = var.automation_enabled ? local.control_planes : {}

  triggers_replace = [
    proxmox_virtual_environment_vm.control_plane[each.key].id,
    var.microk8s_channel,
    var.automation_revision,
    filesha256("${path.module}/scripts/install-microk8s.sh"),
  ]

  lifecycle {
    precondition {
      condition     = var.guest_ssh_private_key_path != null && var.guest_ssh_private_key_path != ""
      error_message = "guest_ssh_private_key_path is required when automation_enabled is true."
    }
  }

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-microk8s.sh"
    destination = "/tmp/install-microk8s.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "sed -i 's/\\r$//' /tmp/install-microk8s.sh",
      "sudo bash /tmp/install-microk8s.sh '${var.microk8s_channel}'",
      "if ! sudo test -e /var/lib/opentofu-control-plane-ip; then printf '%s\\n' '${local.control_plane_ipv4[each.key]}' | sudo tee /var/lib/opentofu-control-plane-ip >/dev/null; fi",
    ]
  }
}

resource "terraform_data" "worker_install" {
  for_each = var.automation_enabled ? local.workers : {}

  triggers_replace = [
    proxmox_virtual_environment_vm.worker[each.key].id,
    var.microk8s_channel,
    var.automation_revision,
    filesha256("${path.module}/scripts/install-microk8s.sh"),
  ]

  lifecycle {
    precondition {
      condition     = var.guest_ssh_private_key_path != null && var.guest_ssh_private_key_path != ""
      error_message = "guest_ssh_private_key_path is required when automation_enabled is true."
    }
    precondition {
      condition     = local.max_worker_hugepage_mb >= 0 && var.hugepages_1g * 1024 + var.hugepages_2m * 2 <= local.max_worker_hugepage_mb
      error_message = "Worker hugepage pools exceed memory available after worker_os_reserved_memory_mb."
    }
  }

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-microk8s.sh"
    destination = "/tmp/install-microk8s.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "sed -i 's/\\r$//' /tmp/install-microk8s.sh",
      "sudo bash /tmp/install-microk8s.sh '${var.microk8s_channel}'",
    ]
  }
}

resource "terraform_data" "control_plane_reboot" {
  for_each = var.automation_enabled ? local.control_planes : {}

  depends_on       = [terraform_data.control_plane_install]
  triggers_replace = [terraform_data.control_plane_install[each.key].id]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "if sudo test -f /var/run/reboot-required; then sudo systemd-run --unit=opentofu-control-plane-reboot --on-active=5s /usr/bin/systemctl reboot; else echo 'Control-plane reboot not required'; fi",
    ]
  }
}

resource "time_sleep" "control_plane_reboot_wait" {
  for_each = var.automation_enabled ? local.control_planes : {}

  depends_on      = [terraform_data.control_plane_reboot]
  create_duration = var.worker_reboot_wait
  triggers = {
    reboot_id = terraform_data.control_plane_reboot[each.key].id
  }
}

resource "terraform_data" "control_plane_ip_guard" {
  for_each = var.automation_enabled ? local.control_planes : {}

  depends_on = [time_sleep.control_plane_reboot_wait]
  triggers_replace = [
    proxmox_virtual_environment_vm.control_plane[each.key].id,
    local.control_plane_ipv4[each.key],
  ]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "recorded=$(sudo cat /var/lib/opentofu-control-plane-ip); if [ \"$recorded\" != '${local.control_plane_ipv4[each.key]}' ]; then echo 'Control-plane IP drift detected: installed='\"$recorded\"' current=${local.control_plane_ipv4[each.key]}. Restore the original address or perform an explicit MicroK8s address migration.' >&2; exit 1; fi",
    ]
  }
}

resource "terraform_data" "control_plane_verify" {
  for_each = var.automation_enabled ? local.control_planes : {}

  depends_on       = [terraform_data.control_plane_ip_guard]
  triggers_replace = [time_sleep.control_plane_reboot_wait[each.key].id]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "test ! -f /var/run/reboot-required",
      "sudo microk8s status --wait-ready --timeout 600",
    ]
  }
}

resource "terraform_data" "worker_configuration" {
  for_each = var.automation_enabled ? local.workers : {}

  depends_on = [terraform_data.worker_install]
  triggers_replace = [
    proxmox_virtual_environment_vm.worker[each.key].id,
    var.hugepages_1g,
    var.hugepages_2m,
    var.worker_os_reserved_memory_mb,
    join(",", local.worker_data_macs[each.key]),
    join(",", [for i, mac in local.worker_data_macs[each.key] : mac if contains(var.worker_vfio_nic_indexes, i)]),
    var.automation_revision,
    filesha256("${path.module}/scripts/configure-worker.sh"),
    filesha256("${path.module}/scripts/bind-worker-vfio"),
    filesha256("${path.module}/scripts/verify-worker-config"),
  ]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/configure-worker.sh"
    destination = "/tmp/configure-worker.sh"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/bind-worker-vfio"
    destination = "/tmp/bind-worker-vfio"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/worker-vfio-bind.service"
    destination = "/tmp/worker-vfio-bind.service"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/verify-worker-config"
    destination = "/tmp/verify-worker-config"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/worker-config-verify.service"
    destination = "/tmp/worker-config-verify.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/configure-worker.sh /tmp/bind-worker-vfio /tmp/worker-vfio-bind.service /tmp/verify-worker-config /tmp/worker-config-verify.service",
      "sudo bash /tmp/configure-worker.sh '${var.hugepages_1g}' '${var.hugepages_2m}' '${join(",", local.worker_data_macs[each.key])}' '${join(",", [for i, mac in local.worker_data_macs[each.key] : mac if contains(var.worker_vfio_nic_indexes, i)])}' '${local.max_worker_hugepage_mb}'",
    ]
  }
}

resource "terraform_data" "worker_reboot" {
  for_each = var.automation_enabled ? local.workers : {}

  depends_on       = [terraform_data.worker_configuration]
  triggers_replace = [terraform_data.worker_configuration[each.key].id]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "if sudo test -f /var/lib/opentofu-worker-reboot-required; then sudo rm -f /var/lib/opentofu-worker-reboot-required; sudo systemd-run --unit=opentofu-worker-reboot --on-active=5s /usr/bin/systemctl reboot; else echo 'Worker reboot not required'; fi",
    ]
  }
}

resource "time_sleep" "worker_reboot_wait" {
  for_each = var.automation_enabled ? local.workers : {}

  depends_on      = [terraform_data.worker_reboot]
  create_duration = var.worker_reboot_wait
  triggers = {
    reboot_id = terraform_data.worker_reboot[each.key].id
  }
}

resource "terraform_data" "worker_verify" {
  for_each = var.automation_enabled ? local.workers : {}

  depends_on       = [time_sleep.worker_reboot_wait]
  triggers_replace = [time_sleep.worker_reboot_wait[each.key].id]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "sudo systemctl restart worker-vfio-bind.service",
      "sudo systemctl restart worker-config-verify.service",
      "sudo systemctl is-active worker-vfio-bind.service worker-config-verify.service",
      "sudo /usr/local/sbin/verify-worker-config",
      "command -v dpdk-devbind.py",
    ]
  }
}

resource "terraform_data" "control_plane_token" {
  for_each = var.automation_enabled ? local.secondary_control_planes : {}

  depends_on       = [terraform_data.control_plane_verify]
  triggers_replace = [random_password.control_plane_join_token[each.key].result, var.automation_revision]

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "if ! sudo microk8s kubectl get node '${each.key}' >/dev/null 2>&1; then sudo microk8s add-node --token '${random_password.control_plane_join_token[each.key].result}' --token-ttl 3600; fi",
    ]
  }
}

resource "terraform_data" "control_plane_join" {
  for_each = var.automation_enabled ? local.secondary_control_planes : {}

  depends_on       = [terraform_data.control_plane_token]
  triggers_replace = [terraform_data.control_plane_token[each.key].id]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "if ! sudo microk8s kubectl get node '${local.primary_control_plane_name}' >/dev/null 2>&1; then sudo microk8s join '${local.primary_control_plane_ipv4}:25000/${random_password.control_plane_join_token[each.key].result}'; else echo 'Control plane already joined'; fi",
    ]
  }
}

resource "terraform_data" "worker_token" {
  for_each = var.automation_enabled ? local.workers : {}

  depends_on = [
    terraform_data.control_plane_verify,
    terraform_data.control_plane_join,
    terraform_data.worker_verify,
  ]
  triggers_replace = [random_password.worker_join_token[each.key].result, var.automation_revision]

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "if ! sudo microk8s kubectl get node '${each.key}' >/dev/null 2>&1; then sudo microk8s add-node --token '${random_password.worker_join_token[each.key].result}' --token-ttl 3600; fi",
    ]
  }
}

resource "terraform_data" "worker_join" {
  for_each = var.automation_enabled ? local.workers : {}

  depends_on = [terraform_data.worker_token]
  triggers_replace = [
    terraform_data.worker_token[each.key].id,
    local.primary_control_plane_ipv4,
    var.automation_revision,
  ]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "if ! sudo microk8s kubectl get node '${local.primary_control_plane_name}' >/dev/null 2>&1; then sudo microk8s join '${local.primary_control_plane_ipv4}:25000/${random_password.worker_join_token[each.key].result}' --worker; else echo 'Worker already joined'; fi",
    ]
  }
}

resource "terraform_data" "worker_post_join_verify" {
  for_each = var.automation_enabled ? local.workers : {}

  depends_on       = [terraform_data.worker_join]
  triggers_replace = [terraform_data.worker_join[each.key].id]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo microk8s status --wait-ready --timeout 600",
      "sudo microk8s status | grep -F 'acting as a node in a cluster'",
      "pgrep -a kubelite | grep -F -- '--start-control-plane=false'",
      "sudo snap services microk8s.daemon-apiserver-proxy | grep -Eq 'enabled[[:space:]]+active'",
    ]
  }
}

resource "terraform_data" "addons" {
  count = var.automation_enabled ? 1 : 0

  depends_on = [
    terraform_data.control_plane_join,
    terraform_data.worker_post_join_verify,
  ]
  triggers_replace = [
    var.enable_hostpath_storage,
    var.enable_multus,
    var.multus_version,
    var.multus_memory_request,
    var.multus_memory_limit,
    var.automation_revision,
    filesha256("${path.module}/scripts/configure-addons.sh"),
  ]

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/configure-addons.sh"
    destination = "/tmp/configure-addons.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/configure-addons.sh",
      "sudo bash /tmp/configure-addons.sh '${var.enable_hostpath_storage}' '${var.enable_multus}' '${var.multus_version}' '${var.multus_memory_request}' '${var.multus_memory_limit}'",
    ]
  }
}

resource "terraform_data" "control_plane_tools" {
  for_each = var.automation_enabled ? local.control_planes : {}

  depends_on = [terraform_data.addons]
  triggers_replace = [
    proxmox_virtual_environment_vm.control_plane[each.key].id,
    var.microk8s_channel,
    var.automation_revision,
    filesha256("${path.module}/scripts/configure-control-plane-tools.sh"),
  ]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/configure-control-plane-tools.sh"
    destination = "/tmp/configure-control-plane-tools.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/configure-control-plane-tools.sh",
      "sudo bash /tmp/configure-control-plane-tools.sh 'v${local.microk8s_minor}'",
    ]
  }
}

resource "terraform_data" "cluster_health" {
  count = var.automation_enabled ? 1 : 0

  depends_on = [
    terraform_data.control_plane_tools,
    terraform_data.worker_post_join_verify,
  ]
  triggers_replace = [
    join(",", local.expected_node_names),
    var.microk8s_channel,
    var.enable_hostpath_storage,
    var.enable_multus,
    var.multus_version,
    var.multus_memory_request,
    var.multus_memory_limit,
    var.automation_revision,
    filesha256("${path.module}/scripts/verify-cluster.sh"),
  ]

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = var.guest_ssh_port
    user        = var.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/verify-cluster.sh"
    destination = "/tmp/verify-cluster.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/verify-cluster.sh",
      "sudo bash /tmp/verify-cluster.sh '${length(local.expected_node_names)}' '${join(",", local.expected_node_names)}' '${local.microk8s_minor}' '${var.enable_hostpath_storage}' '${var.enable_multus}' '${var.multus_version}' '${var.multus_memory_request}' '${var.multus_memory_limit}' '${local.primary_control_plane_ipv4}'",
    ]
  }
}
