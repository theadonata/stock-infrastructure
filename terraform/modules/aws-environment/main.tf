# Customer-managed KMS key for this environment (Trivy AWS-0132 pattern
# already established by STOCK-6: encrypt with a CMK instead of an
# AWS-managed default, for auditability/key-rotation control). Reused by
# both eks.tf (cluster secrets envelope encryption) and the node group's
# EBS volumes, rather than minting a key per resource - this is a
# single-app-per-environment cluster, not a multi-tenant one where blast
# radius would argue for separating them.
resource "aws_kms_key" "this" {
  description         = "CMK for the ${var.environment_name} environment (EKS secrets + node EBS encryption)"
  enable_key_rotation = true
}
