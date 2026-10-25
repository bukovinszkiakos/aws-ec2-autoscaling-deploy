resource "aws_security_group" "instance" {
  name   = "${var.name}-instance"
  vpc_id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "instance_http_alb" {
  security_group_id            = aws_security_group.instance.id
  referenced_security_group_id = var.alb_security_group_id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "instance_all" {
  security_group_id = aws_security_group.instance.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
