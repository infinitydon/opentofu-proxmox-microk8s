output "cluster_ready" {
  value      = var.automation.enabled ? true : null
  depends_on = [terraform_data.cluster_health]
}
