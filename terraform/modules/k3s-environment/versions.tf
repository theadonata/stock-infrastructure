# Applied before bootstrap-environment — installs k3s itself. Kept as its
# own environment/state (not folded into bootstrap) because bootstrap's
# kubernetes/helm providers need a real kubeconfig file to already exist
# when Terraform configures them; bundling k3s install into the same apply
# as resources that require a live kubeconfig is a well-known Terraform
# anti-pattern (provider configuration isn't reliably deferred until after
# an in-apply-created dependency exists).
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
