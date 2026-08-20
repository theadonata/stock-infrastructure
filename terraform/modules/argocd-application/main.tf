# Generic Argo CD Application, parameterized per environment (dev/staging)
# by the calling environments/<env>/main.tf. Replaces the plan's original
# hand-written argocd-apps/<env>-app.yaml (kubectl apply -f) with a
# Terraform-managed resource, so both Applications are declared alongside
# their namespace (../namespace) in one `terraform apply` per environment.
#
# Multi-source: source 1 is the Helm chart (rendered via `helm template`,
# Argo CD's own hook annotations drive ordering — see backend-migrate-job.yaml
# in the chart); source 2 is the plain-manifest secrets directory, applied
# as-is since SealedSecret ciphertext has nothing to template.
locals {
  application_manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.app_name
      namespace = var.argocd_namespace
      # Ensures Argo CD's own resources here are cleaned up if this
      # Application is ever deleted, rather than leaking a cache entry.
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      sources = [
        {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = var.chart_path
          helm = {
            valueFiles = var.values_files
          }
        },
        {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = var.secrets_path
          directory = {
            recurse = false
          }
        },
      ]
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.destination_namespace
      }
      # The destination namespace is created by ../namespace, not by Argo CD
      # (no CreateNamespace=true syncOption) — keeps ownership of that
      # resource in exactly one place.
      syncPolicy = var.automated_sync ? {
        automated = {
          prune    = var.prune
          selfHeal = var.self_heal
        }
        } : {
        # Explicit empty object: no `automated` block means sync only
        # happens when triggered by hand (staging's human-gated promotion).
      }
    }
  }
}

resource "kubectl_manifest" "application" {
  yaml_body = yamlencode(local.application_manifest)
}
