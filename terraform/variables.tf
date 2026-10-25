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

variable "environment" {
  description = "Deployment environment name, used as a resource name suffix."
  type        = string
  default     = "demo"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository to pull images from."
  type        = string
  default     = "beacon-api"
}

variable "image_tag" {
  description = "Docker image tag (Git commit SHA) to deploy. No default: every apply must specify the exact version."
  type        = string
}
