locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_availability_zones" "available" {}
