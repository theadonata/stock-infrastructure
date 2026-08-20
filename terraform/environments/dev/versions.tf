# Phase 1 of gitops-plan.md: dev namespace + Argo CD Application, fully
# automated sync. Requires environments/bootstrap to already be applied
# (Argo CD's Application CRD must exist in the cluster before this runs).
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
