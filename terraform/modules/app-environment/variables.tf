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

variable "namespace_name" {
  description = "Kubernetes namespace this environment's Application deploys into, e.g. stock-hpp-dev or monitoring."
  type        = string
}

variable "app_name" {
  description = "Argo CD Application name, e.g. stock-hpp-dev."
  type        = string
}

variable "repo_url" {
  description = "Git URL of this repo (stock-infrastructure)."
  type        = string
  default     = "https://github.com/theadonata/stock-infrastructure.git"
}

variable "target_revision" {
  description = "Git branch Argo CD tracks."
  type        = string
  default     = "main"
}

variable "chart_path" {
  description = "Path within the repo to the Helm chart."
  type        = string
  default     = "charts/stock-hpp"
}

variable "values_files" {
  description = "Helm values files (relative to chart_path) to layer, in order."
  type        = list(string)
}

variable "secrets_path" {
  description = "Path within the repo to this environment's SealedSecret manifests directory, e.g. secrets/dev. Leave null for a single-source Application whose chart already carries its own SealedSecrets (see docs/adr/0003-observability-stack.md)."
  type        = string
  default     = null
}

variable "automated_sync" {
  description = "true = Argo CD auto-syncs on every new commit. false = sync must be triggered manually."
  type        = bool
}

variable "prune" {
  description = "Only used when automated_sync is true: whether Argo CD deletes resources removed from git."
  type        = bool
  default     = true
}

variable "self_heal" {
  description = "Only used when automated_sync is true: whether Argo CD reverts manual in-cluster drift back to git state."
  type        = bool
  default     = true
}
