variable "k3s_version" {
  description = "Pinned k3s version (passed as INSTALL_K3S_VERSION), e.g. v1.36.3+k3s1. Check https://github.com/k3s-io/k3s/releases before bumping."
  type        = string
}

variable "kubeconfig_path" {
  description = "Where to write the kubeconfig k3s generates. A leading ~ is expanded to $HOME by the install script itself (Terraform providers do this automatically for config_path, but this module's shell script has to do it explicitly)."
  type        = string
}
