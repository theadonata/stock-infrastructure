output "smoke_test_bucket" {
  description = "Confirms the aws provider actually reached Floci and created a (emulated) resource."
  value       = aws_s3_bucket.smoke_test.bucket
}
