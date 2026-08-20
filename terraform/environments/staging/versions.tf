# Phase 2 of gitops-plan.md: staging namespace + Argo CD Application, manual
# sync (the deliberate human-gated promotion step). Requires
# environments/bootstrap to already be applied.
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
