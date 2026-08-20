output "kubeconfig_path" {
  description = "Path the kubeconfig was written to — feed this into environments/bootstrap, dev, and staging's own kubeconfig_path variable."
  value       = var.kubeconfig_path

  depends_on = [null_resource.kubeconfig]
}
