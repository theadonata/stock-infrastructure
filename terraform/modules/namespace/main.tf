# Thin wrapper around kubernetes_namespace so every environment creates its
# app namespace the same way, with the same label convention, instead of
# repeating the resource block in each environments/<env>/main.tf.
resource "kubernetes_namespace" "this" {
  metadata {
    name = var.name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}
