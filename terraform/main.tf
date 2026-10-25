locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_availability_zones" "available" {}

module "network" {
  source = "./modules/network"

  name = local.name
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "alb" {
  source = "./modules/alb"

  name              = local.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
}

module "compute" {
  source = "./modules/compute"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  alb_security_group_id = module.alb.alb_security_group_id
}
