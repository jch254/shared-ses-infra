provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  enabled_parse_domain_records = {
    for key, record in var.parse_domain_records : key => record
    if record.enabled
  }

  planned_mx_records = {
    for key, record in local.enabled_parse_domain_records : key => {
      zone_key     = record.zone_key
      zone_id      = var.zones[record.zone_key].zone_id
      parse_domain = record.parse_domain
      name         = record.mx_name
      content      = "inbound-smtp.${var.ses_region}.amazonaws.com"
      priority     = record.mx_priority
      ttl          = record.ttl
      proxied      = false
      type         = "MX"
    }
  }

  planned_identity_records = {
    for key, record in local.enabled_parse_domain_records : key => {
      zone_key               = record.zone_key
      zone_id                = var.zones[record.zone_key].zone_id
      parse_domain           = record.parse_domain
      has_verification_token = record.verification_token != null
      dkim_token_count       = length(record.dkim_tokens)
      ttl                    = record.ttl
      proxied                = false
    }
  }
}

# Future module usage, intentionally disabled until existing live Cloudflare DNS
# records are imported or moved.
#
# terraform-modules tag 1.5.0 includes the first low-risk SES primitives.
#
# module "ses_domain_records" {
#   for_each = {
#     for key, record in local.enabled_parse_domain_records : key => record
#     if record.verification_token != null && length(record.dkim_tokens) > 0
#   }
#
#   source = "github.com/jch254/terraform-modules//cloudflare-ses-domain-records?ref=1.5.0"
#
#   zone_id            = var.zones[each.value.zone_key].zone_id
#   domain             = each.value.parse_domain
#   verification_token = each.value.verification_token
#   dkim_tokens        = each.value.dkim_tokens
#   ttl                = each.value.ttl
# }
#
# module "ses_inbound_mx" {
#   for_each = local.enabled_parse_domain_records
#
#   source = "github.com/jch254/terraform-modules//cloudflare-ses-inbound-mx?ref=1.5.0"
#
#   zone_id  = var.zones[each.value.zone_key].zone_id
#   name     = each.value.mx_name
#   region   = var.ses_region
#   priority = each.value.mx_priority
#   ttl      = each.value.ttl
# }
#
# SPF, DMARC, Resend, iCloud, Apple verification, app routing records, and
# product Cloudflare settings are deliberately outside this shared SES boundary.
