variable "namespace" {
  description = "Namespace to install Argo CD into."
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-cd Helm chart version (from https://argoproj.github.io/argo-helm), pinned deliberately rather than left floating."
  type        = string
}
