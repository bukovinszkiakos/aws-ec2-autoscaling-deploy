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
