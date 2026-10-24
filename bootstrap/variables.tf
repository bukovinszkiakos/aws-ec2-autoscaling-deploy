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

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "aws-ec2-autoscaling-deploy"
}
