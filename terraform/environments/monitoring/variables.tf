variable "kubeconfig_path" {
  description = "Path to the k3s kubeconfig."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use. Leave null to use the kubeconfig's current-context."
  type        = string
  default     = null
}

variable "repo_url" {
  description = "Git URL of this repo (stock-infrastructure), the source Argo CD tracks for charts/monitoring."
  type        = string
  default     = "https://github.com/theadonata/stock-infrastructure.git"
}

variable "target_revision" {
  description = "Git branch Argo CD tracks for the monitoring stack."
  type        = string
  default     = "main"
}
