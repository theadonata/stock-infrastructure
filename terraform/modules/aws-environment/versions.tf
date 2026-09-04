# Root module for environments/{aws-production,aws-dr}. Networking (vpc.tf)
# and EKS (eks.tf) as of STOCK-7 - still only the `aws` provider; later AWS
# tickets (Aurora Global, observability - ADRs 0005/0008) will add whatever
# else their own resources require.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
