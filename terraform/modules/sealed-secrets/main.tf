# Installs the Sealed Secrets controller — replaces the plan's original
# `bootstrap/sealed-secrets-install.yaml`. The controller generates its own
# keypair on first run; back up the private key material outside the
# cluster manually (Terraform doesn't manage that key — it's generated
# in-cluster, not passed in).
resource "kubernetes_namespace" "sealed_secrets" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "sealed_secrets" {
  name = "sealed-secrets"
  # The project moved from the bitnami-labs org to bitnami; the old
  # bitnami-labs.github.io chart repo now 404s. Use the current host.
  repository = "https://bitnami.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = var.chart_version
  namespace  = kubernetes_namespace.sealed_secrets.metadata[0].name

  wait    = true
  timeout = 300
}
