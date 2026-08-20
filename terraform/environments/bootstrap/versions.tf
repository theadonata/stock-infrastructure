# Phase 0 of gitops-plan.md: installs the cluster-wide controllers
# (Argo CD, Sealed Secrets) that everything else depends on. Applied once,
# manually, after k3s itself is up (see ../../../bootstrap/k3s-install.md).
# Must run — and its state must exist — before environments/dev or
# environments/staging, since those rely on the Argo CD Application CRD
# this installs being registered in the cluster already.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}
