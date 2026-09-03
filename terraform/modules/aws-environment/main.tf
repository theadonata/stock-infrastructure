# Trivial smoke-test resource (STOCK-6 acceptance criteria): proves the
# Terragrunt -> aws provider -> Floci wiring works end-to-end via
# `terragrunt plan`/`apply`. Later AWS tickets (EKS, Aurora Global,
# networking, observability - ADRs 0005-0008) replace this with the real
# resources; nothing here is meant to survive past that.
resource "aws_s3_bucket" "smoke_test" {
  bucket = "stock-hpp-${var.environment_name}-smoke-test"

  tags = {
    Project     = "stock-hpp"
    Environment = var.environment_name
    Purpose     = "STOCK-6 Floci wiring smoke test - safe to delete"
  }
}

# Trivy AWS-0086/0087/0091/0093: block every public-access avenue on this
# bucket even though it's a throwaway smoke-test resource.
resource "aws_s3_bucket_public_access_block" "smoke_test" {
  bucket = aws_s3_bucket.smoke_test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Trivy AWS-0132: encrypt with a customer-managed KMS key instead of the
# AWS-managed default, for auditability/key-rotation control.
resource "aws_kms_key" "smoke_test" {
  description         = "CMK for the STOCK-6 smoke-test bucket (${var.environment_name})"
  enable_key_rotation = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "smoke_test" {
  bucket = aws_s3_bucket.smoke_test.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.smoke_test.arn
    }
  }
}
