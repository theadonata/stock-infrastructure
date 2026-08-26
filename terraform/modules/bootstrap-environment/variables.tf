variable "kubeconfig_path" {
  description = "Path to the k3s kubeconfig (see ../../../bootstrap/k3s-install.md step 2)."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use. Leave null to use the kubeconfig's current-context (fine for a single-cluster homelab setup)."
  type        = string
  default     = null
}

variable "argocd_chart_version" {
  description = "Pinned argo-cd Helm chart version. Check https://artifacthub.io/packages/helm/argo/argo-cd for newer versions before bumping."
  type        = string
  default     = "10.4.0"
}

variable "sealed_secrets_chart_version" {
  description = "Pinned sealed-secrets Helm chart version. Check https://artifacthub.io/packages/helm/bitnami/sealed-secrets for newer versions before bumping (the project moved from the bitnami-labs org to bitnami)."
  type        = string
  default     = "2.19.2"
}
