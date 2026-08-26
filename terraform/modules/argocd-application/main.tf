# Generic Argo CD Application, parameterized per environment (dev/staging)
# by the calling environments/<env>/main.tf. Replaces the plan's original
# hand-written argocd-apps/<env>-app.yaml (kubectl apply -f) with a
# Terraform-managed resource, so both Applications are declared alongside
# their namespace (../namespace) in one `terraform apply` per environment.
#
# Multi-source by default: source 1 is the Helm chart (rendered via `helm
# template`, Argo CD's own hook annotations drive ordering — see
# backend-migrate-job.yaml in the chart); source 2 is the plain-manifest
# secrets directory, applied as-is since SealedSecret ciphertext has nothing
# to template.
#
# When var.secrets_path is null, `sources` renders with just the chart entry
# — used by environments/monitoring, whose chart carries its own
# SealedSecrets directly in charts/monitoring/templates/ rather than a
# second source. See docs/adr/0003-observability-stack.md: plain sync-wave
# doesn't reliably order resources *across* an Application's multiple
# sources (the stock-hpp-backend-secrets incident this repo already hit),
# so a stack that needs strict ordering and has no per-environment secret
# content keeps everything in one source instead of risking that failure
# mode again. A one-element `sources` list is what Argo CD calls
# single-source in practice — there's nothing left to order *across* — kept
# as `sources` (plural) rather than switching to the singular `source` field
# so both branches build the exact same object shape (Terraform's object
# type unification rejects a conditional between differently-shaped
# objects).
locals {
  chart_source = {
    repoURL        = var.repo_url
    targetRevision = var.target_revision
    path           = var.chart_path
    helm = {
      valueFiles = var.values_files
    }
  }

  secrets_source = {
    repoURL        = var.repo_url
    targetRevision = var.target_revision
    path           = var.secrets_path
    directory = {
      recurse = false
    }
  }

  source_block = {
    # concat(), not a ternary between two differently-shaped/-lengthed list
    # literals — Terraform's object type unification rejects that (tested;
    # "Inconsistent conditional result types"). The empty-list branch below
    # has no elements to conflict with local.chart_source's type, so this
    # unifies cleanly either way.
    sources = concat([local.chart_source], var.secrets_path == null ? [] : [local.secrets_source])
  }

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
    spec = merge(
      {
        project = "default"
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
      },
      local.source_block
    )
  }
}

resource "kubectl_manifest" "application" {
  yaml_body = yamlencode(local.application_manifest)
}
