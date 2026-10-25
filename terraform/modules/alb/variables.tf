variable "name" {
  description = "Name prefix applied to all resources in this module."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to deploy into."
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets for the ALB."
  type        = list(string)
}

variable "health_check_path" {
  description = "HTTP path used for ALB target group health checks."
  type        = string
  default     = "/health"
}
