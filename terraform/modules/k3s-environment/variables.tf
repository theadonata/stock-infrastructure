variable "k3s_version" {
  description = "Pinned k3s version. Check https://github.com/k3s-io/k3s/releases before bumping."
  type        = string
  default     = "v1.36.3+k3s1"
}

variable "kubeconfig_path" {
  description = "Where to write the kubeconfig. bootstrap-environment, app-environment (dev/staging/monitoring)'s own kubeconfig_path variables must point at the same path."
  type        = string
  default     = "~/.kube/config"
}
