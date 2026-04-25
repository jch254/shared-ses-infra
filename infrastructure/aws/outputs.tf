output "aws_region" {
  description = "Default AWS region used for local/backend-compatible conventions."
  value       = var.aws_region
}

output "ses_region" {
  description = "AWS region for SES inbound receiving."
  value       = var.ses_region
}

output "environment" {
  description = "Deployment environment label."
  value       = var.environment
}

output "route_keys" {
  description = "All configured route keys."
  value       = keys(var.routes)
}

output "enabled_route_keys" {
  description = "Route keys enabled for future SES routing."
  value       = keys(local.enabled_routes)
}

output "route_summaries" {
  description = "Non-secret route model summary for review before any live resources are created."
  value       = local.route_summaries
}
