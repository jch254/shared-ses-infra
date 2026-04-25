output "environment" {
  description = "Deployment environment label."
  value       = var.environment
}

output "ses_region" {
  description = "AWS region for SES inbound receiving."
  value       = var.ses_region
}

output "zone_keys" {
  description = "Configured Cloudflare zone keys."
  value       = keys(var.zones)
}

output "enabled_parse_domain_keys" {
  description = "Parse-domain DNS model keys enabled for future Cloudflare management."
  value       = keys(local.enabled_parse_domain_records)
}

output "planned_mx_records" {
  description = "Inert review output showing future SES inbound MX records."
  value       = local.planned_mx_records
}

output "planned_identity_records" {
  description = "Inert review output showing future SES verification and DKIM record readiness."
  value       = local.planned_identity_records
}
