output "app_url" {
  description = "HTTP URL of the application."
  value       = "http://${module.alb.alb_dns_name}"
}
