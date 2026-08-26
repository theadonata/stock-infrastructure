# Shared by dev, staging, and monitoring (see main.tf) — namespace +
# Argo CD Application, one per environment. Requires environments/bootstrap
# to already be applied (Argo CD's Application CRD must exist in the
# cluster before this runs).
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}
