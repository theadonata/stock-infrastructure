module "k3s" {
  source          = "../../modules/k3s"
  k3s_version     = var.k3s_version
  kubeconfig_path = var.kubeconfig_path
}
