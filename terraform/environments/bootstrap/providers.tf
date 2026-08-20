# Both providers point at the same kubeconfig — set kubeconfig_path in
# terraform.tfvars (copy terraform.tfvars.example) to your local kubeconfig
# from bootstrap/k3s-install.md step 2.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
