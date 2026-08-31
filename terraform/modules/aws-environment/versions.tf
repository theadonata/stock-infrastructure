# Root module for environments/{aws-production,aws-dr}. Only the `aws`
# provider is needed at this prefactor stage — later AWS tickets (EKS,
# Aurora Global, networking, observability - ADRs 0005-0008) will add
# whatever else their own resources require.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
