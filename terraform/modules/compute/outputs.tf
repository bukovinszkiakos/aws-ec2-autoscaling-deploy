output "instance_profile_name" {
  description = "Name of the EC2 instance profile."
  value       = aws_iam_instance_profile.ec2.name
}

output "instance_security_group_id" {
  description = "ID of the instance security group."
  value       = aws_security_group.instance.id
}

output "launch_template_id" {
  description = "ID of the EC2 launch template."
  value       = aws_launch_template.this.id
}
