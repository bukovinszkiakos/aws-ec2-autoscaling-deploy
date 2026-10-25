locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_availability_zones" "available" {}

module "network" {
  source = "./modules/network"

  name = local.name
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}
