variable "name" {
  description = "Name prefix applied to all resources in this module."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to deploy into."
  type        = string
}

variable "alb_security_group_id" {
  description = "ID of the ALB security group, used to restrict instance ingress."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ecr_repository_url" {
  description = "Full URL of the ECR repository (used for docker pull and docker run)."
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy."
  type        = string
}

variable "aws_region" {
  description = "AWS region, used in the ECR login command."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets for the Auto Scaling Group."
  type        = list(string)
}

variable "target_group_arn" {
  description = "ARN of the ALB target group to attach instances to."
  type        = string
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group."
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group."
  type        = number
  default     = 2
}
