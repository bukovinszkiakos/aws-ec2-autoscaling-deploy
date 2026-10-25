output "state_bucket_name" {
  description = "Name of the S3 bucket used to store Terraform state."
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_repository_name" {
  description = "Name of the ECR repository."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository (used when pushing or pulling images)."
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC."
  value       = aws_iam_role.github_actions.arn
}
