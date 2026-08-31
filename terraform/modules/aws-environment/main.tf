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
