# Installs Argo CD itself — replaces the plan's original
# `bootstrap/argocd-install.yaml` (kubectl apply -f) with a Terraform-managed
# helm_release, so the whole bootstrap layer is declarative and diffable
# instead of a one-shot imperative apply.
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Minimal-first per gitops-plan.md: no extra values beyond namespace/version
  # for now. Add a values file here (e.g. for Ingress-exposing the Argo CD UI
  # instead of port-forwarding) once that becomes a real need.
  wait = true
  # 900s, not Helm's/this provider's 300s default: a first-time install on a
  # fresh node has to pull ~7 images (redis, dex, server, repo-server,
  # application-controller, applicationset-controller,
  # notifications-controller) with nothing cached, which can take a while
  # depending on network speed. A tight timeout here doesn't actually fail
  # the install — Kubernetes keeps reconciling in the background regardless
  # of whether Terraform is still watching — it just makes `terraform apply`
  # report a scary-looking error for something that finishes fine seconds
  # later. Confirmed in practice: a 600s timeout here fired even though the
  # release had already succeeded and all pods came up healthy shortly after.
  timeout = 900
}
