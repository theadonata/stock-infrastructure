# Local state — see ../bootstrap/backend.tf for the reasoning. Separate
# state file from bootstrap/dev/staging since each is its own directory
# (and could reasonably be applied by different people/at different times).
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
