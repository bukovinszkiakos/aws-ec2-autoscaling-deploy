locals {
  ecr_registry_host = split("/", var.ecr_repository_url)[0]
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.instance.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region         = var.aws_region
    ecr_registry_host  = local.ecr_registry_host
    ecr_repository_url = var.ecr_repository_url
    image_tag          = var.image_tag
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-app"
    }
  }
}
