# Root module for environments/k3s. Module block name (`k3s`) kept
# identical to what environments/k3s/main.tf used to declare at root
# level — see ../app-environment/main.tf's comment for why that matters
# for state-address continuity.
module "k3s" {
  source          = "../k3s"
  k3s_version     = var.k3s_version
  kubeconfig_path = var.kubeconfig_path
}
