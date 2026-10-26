variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resources."
  type        = string
  default     = "beacon"
}

variable "github_owner" {
  description = "GitHub organisation or user name that owns the repository."
  type        = string
  default     = "bukovinszkiakos"
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of the owner. Required when the repository has use_immutable_subject enabled so that OIDC sub claims include the owner ID."
  type        = string
  default     = "163352755"
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "aws-ec2-autoscaling-deploy"
}

variable "github_repo_id" {
  description = "Numeric GitHub ID of the repository. Required when the repository has use_immutable_subject enabled so that OIDC sub claims include the repository ID."
  type        = string
  default     = "1429775315"
}

variable "create_oidc_provider" {
  description = "Set to true to create the GitHub Actions OIDC provider. An AWS account can only have one provider per issuer URL; if another project already created it, leave this false and Terraform will look it up instead."
  type        = bool
  default     = false
}
