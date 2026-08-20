terraform {
  required_providers {
    # kubectl_manifest (not kubernetes_manifest) deliberately: Terraform's
    # own kubernetes_manifest resource needs the target CRD's OpenAPI schema
    # already registered in the cluster at *plan* time, which only works
    # here because environments/bootstrap (installing Argo CD, which
    # registers the Application CRD) is applied as a separate, earlier
    # Terraform run. kubectl_manifest sidesteps that ordering dependency
    # entirely by just posting the YAML, which is simpler and more robust
    # for a CRD instance like this.
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
}
