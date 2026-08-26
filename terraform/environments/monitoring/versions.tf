# Shared Prometheus + Grafana + Loki + Alloy + Alertmanager stack — one
# instance covering both stock-hpp-dev and stock-hpp-staging (see
# ../../../docs/adr/0003-observability-stack.md), not phased per environment
# the way dev/staging are. Requires environments/bootstrap to already be
# applied (Argo CD's Application CRD must exist in the cluster before this
# runs).
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
