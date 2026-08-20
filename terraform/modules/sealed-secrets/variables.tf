variable "namespace" {
  description = "Namespace to install the Sealed Secrets controller into."
  type        = string
  default     = "sealed-secrets"
}

variable "chart_version" {
  description = "sealed-secrets Helm chart version (from https://bitnami-labs.github.io/sealed-secrets), pinned deliberately rather than left floating."
  type        = string
}
