# Local state, deliberately: this is a single-operator homelab cluster with
# no shared remote-state backend (S3-compatible store, etc.) available yet.
# If that changes, replace this block with a `backend "s3"` (or similar)
# block — the resource config above doesn't need to change either way.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
