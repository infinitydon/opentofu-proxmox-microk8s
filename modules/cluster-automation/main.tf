

locals {
  control_planes     = var.control_planes
  workers            = var.workers
  worker_node_labels = var.worker_node_labels

  microk8s_channel        = var.kubernetes.microk8s_channel
  k9s_version             = var.kubernetes.k9s_version
  kubectl_version         = var.kubernetes.kubectl_version
  helm_version            = var.kubernetes.helm_version
  enable_hostpath_storage = var.addons.hostpath_storage
  enable_multus           = var.addons.multus.enabled
  multus_version          = var.addons.multus.version
  multus_memory_request   = var.addons.multus.memory_request
  multus_memory_limit     = var.addons.multus.memory_limit
  automation_enabled      = var.automation.enabled
  guest_ssh_user          = var.automation.ssh_user
  guest_ssh_port          = var.automation.ssh_port
  automation_revision     = var.automation.revision
  worker_reboot_wait      = var.automation.reboot_wait

  primary_control_plane_name = sort(keys(local.control_planes))[0]
  secondary_control_planes = {
    for name, node in local.control_planes : name => node
    if name != local.primary_control_plane_name
  }
  control_plane_ipv4         = { for name, node in local.control_planes : name => node.management_ipv4 }
  worker_ipv4                = { for name, node in local.workers : name => node.management_ipv4 }
  worker_data_macs           = { for name, node in local.workers : name => node.data_macs }
  primary_control_plane_ipv4 = local.control_plane_ipv4[local.primary_control_plane_name]
  microk8s_minor             = split("/", local.microk8s_channel)[0]
  expected_node_names        = concat(sort(keys(local.control_planes)), sort(keys(local.workers)))
  max_worker_hugepage_mb = {
    for name, worker in local.workers : name => worker.memory_mb - worker.os_reserved_memory_mb
  }
  cloud_init_wait_command = "rc=0; cloud-init status --wait >/tmp/opentofu-cloud-init.log 2>&1 || rc=$?; if [ \"$rc\" -eq 0 ]; then :; elif [ \"$rc\" -eq 2 ] && cloud-init status 2>/dev/null | grep -q '^status: done$'; then echo 'cloud-init completed with recoverable warnings:'; cloud-init status --long 2>/dev/null | sed -n '/^recoverable_errors:/,$p' | sed '/^recoverable_errors:$/d;/^[[:space:]]*$/d' | head -n 20; else echo 'cloud-init did not complete successfully:' >&2; cloud-init status --long >&2 || true; exit \"$rc\"; fi"
}

resource "random_password" "control_plane_join_token" {
  for_each = local.automation_enabled ? local.secondary_control_planes : {}

  length  = 32
  special = false
}

resource "random_password" "worker_join_token" {
  for_each = local.automation_enabled ? local.workers : {}

  length  = 32
  special = false
}

resource "terraform_data" "control_plane_install" {
  for_each = local.automation_enabled ? local.control_planes : {}

  triggers_replace = [
    each.value.id,
    each.value.disk_gb,
    local.microk8s_channel,
    local.automation_revision,
    filesha256("${path.module}/../../scripts/install-microk8s.sh"),
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
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/install-microk8s.sh"
    destination = "/tmp/install-microk8s.sh"
  }

  provisioner "remote-exec" {
    inline = [
      local.cloud_init_wait_command,
      "echo 'cloud-init completed on ${each.key}'",
      "sed -i 's/\\r$//' /tmp/install-microk8s.sh",
      "sudo bash /tmp/install-microk8s.sh '${local.microk8s_channel}' >/tmp/opentofu-install-microk8s.log 2>&1 || { rc=$?; echo 'MicroK8s installation failed; last 80 log lines:' >&2; sudo tail -n 80 /tmp/opentofu-install-microk8s.log >&2; exit $rc; }",
      "echo 'MicroK8s installation completed on ${each.key}'",
      "if ! sudo test -e /var/lib/opentofu-control-plane-ip; then printf '%s\\n' '${local.control_plane_ipv4[each.key]}' | sudo tee /var/lib/opentofu-control-plane-ip >/dev/null; fi",
    ]
  }
}

resource "terraform_data" "worker_install" {
  for_each = local.automation_enabled ? local.workers : {}

  triggers_replace = [
    each.value.id,
    each.value.disk_gb,
    local.microk8s_channel,
    local.automation_revision,
    filesha256("${path.module}/../../scripts/install-microk8s.sh"),
  ]

  lifecycle {
    precondition {
      condition     = var.guest_ssh_private_key_path != null && var.guest_ssh_private_key_path != ""
      error_message = "guest_ssh_private_key_path is required when automation_enabled is true."
    }
    precondition {
      condition     = local.max_worker_hugepage_mb[each.key] >= 0 && each.value.hugepages_1g * 1024 + each.value.hugepages_2m * 2 <= local.max_worker_hugepage_mb[each.key]
      error_message = "Worker hugepage pools exceed memory available after worker_os_reserved_memory_mb."
    }
  }

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/install-microk8s.sh"
    destination = "/tmp/install-microk8s.sh"
  }

  provisioner "remote-exec" {
    inline = [
      local.cloud_init_wait_command,
      "echo 'cloud-init completed on ${each.key}'",
      "sed -i 's/\\r$//' /tmp/install-microk8s.sh",
      "sudo bash /tmp/install-microk8s.sh '${local.microk8s_channel}' >/tmp/opentofu-install-microk8s.log 2>&1 || { rc=$?; echo 'MicroK8s installation failed; last 80 log lines:' >&2; sudo tail -n 80 /tmp/opentofu-install-microk8s.log >&2; exit $rc; }",
      "echo 'MicroK8s installation completed on ${each.key}'",
    ]
  }
}

resource "terraform_data" "control_plane_reboot" {
  for_each = local.automation_enabled ? local.control_planes : {}

  depends_on       = [terraform_data.control_plane_install]
  triggers_replace = [terraform_data.control_plane_install[each.key].id]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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
  for_each = local.automation_enabled ? local.control_planes : {}

  depends_on      = [terraform_data.control_plane_reboot]
  create_duration = local.worker_reboot_wait
  triggers = {
    reboot_id = terraform_data.control_plane_reboot[each.key].id
  }
}

resource "terraform_data" "control_plane_ip_guard" {
  for_each = local.automation_enabled ? local.control_planes : {}

  depends_on = [time_sleep.control_plane_reboot_wait]
  triggers_replace = [
    each.value.id,
    local.control_plane_ipv4[each.key],
  ]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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
  for_each = local.automation_enabled ? local.control_planes : {}

  depends_on       = [terraform_data.control_plane_ip_guard]
  triggers_replace = [time_sleep.control_plane_reboot_wait[each.key].id]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      local.cloud_init_wait_command,
      "test ! -f /var/run/reboot-required",
      "sudo microk8s status --wait-ready --timeout 600",
    ]
  }
}

resource "terraform_data" "worker_configuration" {
  for_each = local.automation_enabled ? local.workers : {}

  depends_on = [terraform_data.worker_install]
  triggers_replace = {
    worker_vm_id            = each.value.id
    pool_name               = each.value.pool_name
    hugepages_1g            = each.value.hugepages_1g
    hugepages_2m            = each.value.hugepages_2m
    os_reserved_memory_mb   = each.value.os_reserved_memory_mb
    data_macs_csv           = join(",", local.worker_data_macs[each.key])
    vfio_macs_csv           = join(",", [for i, mac in local.worker_data_macs[each.key] : mac if contains(each.value.vfio_nic_indexes, i)])
    automation_revision     = local.automation_revision
    configure_script_sha256 = filesha256("${path.module}/../../scripts/configure-worker.sh")
    bind_script_sha256      = filesha256("${path.module}/../../scripts/bind-worker-vfio")
    verify_script_sha256    = filesha256("${path.module}/../../scripts/verify-worker-config")
  }

  input = {
    operation             = "configure_worker_runtime"
    node                  = each.key
    pool                  = each.value.pool_name
    hugepages_1g          = each.value.hugepages_1g
    hugepages_2m          = each.value.hugepages_2m
    data_nic_count        = each.value.data_nic_count
    vfio_nic_indexes      = sort(tolist(each.value.vfio_nic_indexes))
    os_reserved_memory_mb = each.value.os_reserved_memory_mb
  }

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/configure-worker.sh"
    destination = "/tmp/configure-worker.sh"
  }
  provisioner "file" {
    source      = "${path.module}/../../scripts/bind-worker-vfio"
    destination = "/tmp/bind-worker-vfio"
  }
  provisioner "file" {
    source      = "${path.module}/../../scripts/worker-vfio-bind.service"
    destination = "/tmp/worker-vfio-bind.service"
  }
  provisioner "file" {
    source      = "${path.module}/../../scripts/verify-worker-config"
    destination = "/tmp/verify-worker-config"
  }
  provisioner "file" {
    source      = "${path.module}/../../scripts/worker-config-verify.service"
    destination = "/tmp/worker-config-verify.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/configure-worker.sh /tmp/bind-worker-vfio /tmp/worker-vfio-bind.service /tmp/verify-worker-config /tmp/worker-config-verify.service",
      "sudo bash /tmp/configure-worker.sh '${each.value.hugepages_1g}' '${each.value.hugepages_2m}' '${join(",", local.worker_data_macs[each.key])}' '${join(",", [for i, mac in local.worker_data_macs[each.key] : mac if contains(each.value.vfio_nic_indexes, i)])}' '${local.max_worker_hugepage_mb[each.key]}' >/tmp/opentofu-configure-worker.log 2>&1 || { rc=$?; echo 'Worker configuration failed; last 80 log lines:' >&2; sudo tail -n 80 /tmp/opentofu-configure-worker.log >&2; exit $rc; }",
      "echo 'VFIO and hugepage configuration completed on ${each.key}'",
    ]
  }
}

resource "terraform_data" "worker_reboot" {
  for_each = local.automation_enabled ? local.workers : {}

  depends_on       = [terraform_data.worker_configuration]
  triggers_replace = [terraform_data.worker_configuration[each.key].id]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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
  for_each = local.automation_enabled ? local.workers : {}

  depends_on      = [terraform_data.worker_reboot]
  create_duration = local.worker_reboot_wait
  triggers = {
    reboot_id = terraform_data.worker_reboot[each.key].id
  }
}

resource "terraform_data" "worker_verify" {
  for_each = local.automation_enabled ? local.workers : {}

  depends_on       = [time_sleep.worker_reboot_wait]
  triggers_replace = [time_sleep.worker_reboot_wait[each.key].id]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      local.cloud_init_wait_command,
      "sudo systemctl restart worker-vfio-bind.service",
      "sudo systemctl restart worker-config-verify.service",
      "sudo systemctl is-active worker-vfio-bind.service worker-config-verify.service",
      "sudo /usr/local/sbin/verify-worker-config",
      "command -v dpdk-devbind.py",
    ]
  }
}

resource "terraform_data" "control_plane_token" {
  for_each = local.automation_enabled ? local.secondary_control_planes : {}

  depends_on       = [terraform_data.control_plane_verify]
  triggers_replace = [random_password.control_plane_join_token[each.key].result, local.automation_revision]

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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
  for_each = local.automation_enabled ? local.secondary_control_planes : {}

  depends_on       = [terraform_data.control_plane_token]
  triggers_replace = [terraform_data.control_plane_token[each.key].id]

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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
  for_each = local.automation_enabled ? local.workers : {}

  depends_on = [
    terraform_data.control_plane_verify,
    terraform_data.control_plane_join,
    terraform_data.worker_verify,
  ]
  triggers_replace = [random_password.worker_join_token[each.key].result, local.automation_revision]

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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
  for_each = local.automation_enabled ? local.workers : {}

  depends_on = [terraform_data.worker_token]
  triggers_replace = [
    terraform_data.worker_token[each.key].id,
    local.primary_control_plane_ipv4,
    local.automation_revision,
  ]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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
  for_each = local.automation_enabled ? local.workers : {}

  depends_on       = [terraform_data.worker_join]
  triggers_replace = [terraform_data.worker_join[each.key].id]

  connection {
    type        = "ssh"
    host        = local.worker_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
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

resource "terraform_data" "worker_labels" {
  for_each = local.automation_enabled ? local.workers : {}

  depends_on = [terraform_data.worker_post_join_verify]
  triggers_replace = {
    worker_join_verification_id = terraform_data.worker_post_join_verify[each.key].id
    labels_sha256               = sha256(jsonencode(local.worker_node_labels[each.key]))
    script_sha256               = filesha256("${path.module}/../../scripts/configure-worker-labels.sh")
  }

  input = {
    operation                    = "reconcile_worker_labels"
    node                         = each.key
    labels                       = local.worker_node_labels[each.key]
    remove_absent_managed_labels = true
    preserve_unmanaged_labels    = true
    verify_after_apply           = true
  }

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/configure-worker-labels.sh"
    destination = "/tmp/configure-worker-labels.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/configure-worker-labels.sh",
      "sudo bash /tmp/configure-worker-labels.sh '${each.key}' '${base64encode(jsonencode(local.worker_node_labels[each.key]))}'",
    ]
  }
}

resource "terraform_data" "addons" {
  count = local.automation_enabled ? 1 : 0

  depends_on = [
    terraform_data.control_plane_join,
    terraform_data.worker_labels,
  ]
  triggers_replace = [
    local.enable_hostpath_storage,
    local.enable_multus,
    local.multus_version,
    local.multus_memory_request,
    local.multus_memory_limit,
    local.automation_revision,
    filesha256("${path.module}/../../scripts/configure-addons.sh"),
  ]

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/configure-addons.sh"
    destination = "/tmp/configure-addons.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/configure-addons.sh",
      "sudo bash /tmp/configure-addons.sh '${local.enable_hostpath_storage}' '${local.enable_multus}' '${local.multus_version}' '${local.multus_memory_request}' '${local.multus_memory_limit}' >/tmp/opentofu-configure-addons.log 2>&1 || { rc=$?; echo 'Addon configuration failed; last 80 log lines:' >&2; sudo tail -n 80 /tmp/opentofu-configure-addons.log >&2; exit $rc; }",
      "echo 'Cluster addons configured'",
    ]
  }
}

resource "terraform_data" "control_plane_tools" {
  for_each = local.automation_enabled ? local.control_planes : {}

  depends_on = [terraform_data.addons]
  triggers_replace = {
    control_plane_vm_id = each.value.id
    microk8s_channel    = local.microk8s_channel
    k9s_version         = local.k9s_version
    kubectl_version     = local.kubectl_version
    helm_version        = local.helm_version
    automation_revision = local.automation_revision
    script_sha256       = filesha256("${path.module}/../../scripts/configure-control-plane-tools.sh")
  }

  input = {
    operation                   = "configure_control_plane_tools"
    node                        = each.key
    normal_user                 = local.guest_ssh_user
    kubectl_version             = local.kubectl_version
    enable_kubectl_completion   = true
    install_helm_version        = local.helm_version
    install_k9s_version         = local.k9s_version
    verify_k9s_package_checksum = true
    verify_normal_user_access   = true
  }

  lifecycle {
    precondition {
      condition     = join(".", slice(split(".", local.kubectl_version), 0, 2)) == local.microk8s_minor
      error_message = "kubectl_version must use the same major.minor release as microk8s_channel."
    }
  }

  connection {
    type        = "ssh"
    host        = local.control_plane_ipv4[each.key]
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/configure-control-plane-tools.sh"
    destination = "/tmp/configure-control-plane-tools.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/configure-control-plane-tools.sh",
      "sudo bash /tmp/configure-control-plane-tools.sh 'v${local.microk8s_minor}' '${local.k9s_version}' '${local.kubectl_version}' '${local.helm_version}' >/tmp/opentofu-control-plane-tools.log 2>&1 || { rc=$?; echo 'Control-plane tool installation failed; last 80 log lines:' >&2; sudo tail -n 80 /tmp/opentofu-control-plane-tools.log >&2; exit $rc; }",
      "echo 'kubectl, Bash completion, Helm, and k9s verified on ${each.key}'",
    ]
  }
}

resource "terraform_data" "cluster_health" {
  count = local.automation_enabled ? 1 : 0

  depends_on = [
    terraform_data.control_plane_tools,
    terraform_data.worker_post_join_verify,
  ]
  triggers_replace = {
    expected_nodes_csv    = join(",", local.expected_node_names)
    microk8s_channel      = local.microk8s_channel
    hostpath_enabled      = local.enable_hostpath_storage
    multus_enabled        = local.enable_multus
    multus_version        = local.multus_version
    multus_memory_request = local.multus_memory_request
    multus_memory_limit   = local.multus_memory_limit
    k9s_version           = local.k9s_version
    kubectl_version       = local.kubectl_version
    helm_version          = local.helm_version
    automation_revision   = local.automation_revision
    script_sha256         = filesha256("${path.module}/../../scripts/verify-cluster.sh")
  }

  input = {
    operation       = "verify_cluster_health"
    expected_nodes  = local.expected_node_names
    microk8s_minor  = local.microk8s_minor
    verify_ready    = true
    verify_kubectl  = true
    verify_helm     = true
    verify_k9s      = true
    kubectl_version = local.kubectl_version
    helm_version    = local.helm_version
    verify_hostpath = local.enable_hostpath_storage
    verify_multus   = local.enable_multus
  }

  connection {
    type        = "ssh"
    host        = local.primary_control_plane_ipv4
    port        = local.guest_ssh_port
    user        = local.guest_ssh_user
    private_key = file(var.guest_ssh_private_key_path)
    timeout     = "15m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/verify-cluster.sh"
    destination = "/tmp/verify-cluster.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\\r$//' /tmp/verify-cluster.sh",
      "sudo bash /tmp/verify-cluster.sh '${length(local.expected_node_names)}' '${join(",", local.expected_node_names)}' '${local.microk8s_minor}' '${local.enable_hostpath_storage}' '${local.enable_multus}' '${local.multus_version}' '${local.multus_memory_request}' '${local.multus_memory_limit}' '${local.primary_control_plane_ipv4}' '${local.k9s_version}' '${local.kubectl_version}' '${local.helm_version}'",
    ]
  }
}



