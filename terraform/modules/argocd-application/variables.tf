variable "app_name" {
  description = "Argo CD Application name, e.g. stock-hpp-dev."
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace Argo CD itself runs in (where the Application CR is created)."
  type        = string
  default     = "argocd"
}

variable "destination_namespace" {
  description = "Namespace the rendered chart is deployed into, e.g. stock-hpp-dev."
  type        = string
}

variable "repo_url" {
  description = "Git URL of this repo (stock-infrastructure) — both the Helm chart and the sealed-secrets directory are sourced from it."
  type        = string
}

variable "target_revision" {
  description = "Git branch/tag Argo CD tracks."
  type        = string
  default     = "main"
}

variable "chart_path" {
  description = "Path within the repo to the umbrella Helm chart."
  type        = string
  default     = "charts/stock-hpp"
}

variable "values_files" {
  description = "Helm values files (relative to chart_path) to layer, in order, e.g. [\"values.yaml\", \"values-dev.yaml\"]."
  type        = list(string)
}

variable "secrets_path" {
  description = "Path within the repo to this environment's SealedSecret manifests directory, e.g. secrets/dev."
  type        = string
}

variable "automated_sync" {
  description = "true = Argo CD auto-syncs on every new commit (dev). false = sync must be triggered manually, an extra gate on top of the CI PR-merge gate (staging). See gitops-plan.md Phase 1/2."
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
