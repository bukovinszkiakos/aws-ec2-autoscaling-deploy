output "app_url" {
  description = "HTTP URL of the application."
  value       = "http://${module.alb.alb_dns_name}"
}

output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = module.compute.asg_name
}
