provider "aws" {
  region = var.ses_region
}

locals {
  enabled_routes = {
    for key, route in var.routes : key => route
    if route.enabled
  }

  route_summaries = {
    for key, route in var.routes : key => {
      app_name              = route.app_name
      parse_domain          = route.parse_domain
      recipients            = route.recipients
      raw_bucket_name       = route.raw_bucket_name
      raw_object_prefix     = route.raw_object_prefix
      forwarder_lambda_name = route.forwarder_lambda_name
      has_lambda_arn        = route.forwarder_lambda_arn != null
      parser_endpoint       = route.parser_endpoint
      has_parser_secret     = route.parser_secret_parameter_arn != null
      enabled               = route.enabled
    }
  }

  modeled_routes = {
    gtd_inbound = {
      name                   = "gtd-inbound"
      recipients             = ["parse.namasteapp.tech"]
      enabled                = true
      scan_enabled           = true
      tls_policy             = "Optional"
      s3_bucket_name         = "gtd-ses-emails"
      s3_object_key_prefix   = ""
      lambda_function_arn    = "arn:aws:lambda:ap-southeast-2:352311918919:function:gtd-ses-forwarder"
      lambda_invocation_type = "Event"
      s3_position            = 1
      lambda_position        = 2
    }

    music_submission = {
      name                   = "music-submission"
      recipients             = ["parse.lushauraltreats.com"]
      enabled                = true
      scan_enabled           = true
      tls_policy             = "Optional"
      s3_bucket_name         = "lush-aural-treats-ses-emails"
      s3_object_key_prefix   = ""
      lambda_function_arn    = "arn:aws:lambda:ap-southeast-2:352311918919:function:lush-aural-treats-ses-forwarder"
      lambda_invocation_type = "Event"
      s3_position            = 1
      lambda_position        = 2
    }
  }
}

# Imported-state model: these modules own the live shared SES receipt rule set
# and receipt rules. Activation remains intentionally unmanaged here.
module "ses_receipt_rule_set" {
  source = "github.com/jch254/terraform-modules//ses-receipt-rule-set?ref=1.6.0"

  name     = "shared-inbound-mail-rules"
  activate = false
}

module "gtd_inbound_rule" {
  source = "github.com/jch254/terraform-modules//ses-receipt-rule?ref=1.6.0"

  name                   = local.modeled_routes.gtd_inbound.name
  rule_set_name          = module.ses_receipt_rule_set.name
  recipients             = local.modeled_routes.gtd_inbound.recipients
  enabled                = local.modeled_routes.gtd_inbound.enabled
  scan_enabled           = local.modeled_routes.gtd_inbound.scan_enabled
  tls_policy             = local.modeled_routes.gtd_inbound.tls_policy
  s3_bucket_name         = local.modeled_routes.gtd_inbound.s3_bucket_name
  s3_object_key_prefix   = local.modeled_routes.gtd_inbound.s3_object_key_prefix
  lambda_function_arn    = local.modeled_routes.gtd_inbound.lambda_function_arn
  lambda_invocation_type = local.modeled_routes.gtd_inbound.lambda_invocation_type
  s3_position            = local.modeled_routes.gtd_inbound.s3_position
  lambda_position        = local.modeled_routes.gtd_inbound.lambda_position
}

module "music_submission_rule" {
  source = "github.com/jch254/terraform-modules//ses-receipt-rule?ref=1.6.0"

  name                   = local.modeled_routes.music_submission.name
  rule_set_name          = module.ses_receipt_rule_set.name
  recipients             = local.modeled_routes.music_submission.recipients
  enabled                = local.modeled_routes.music_submission.enabled
  scan_enabled           = local.modeled_routes.music_submission.scan_enabled
  tls_policy             = local.modeled_routes.music_submission.tls_policy
  s3_bucket_name         = local.modeled_routes.music_submission.s3_bucket_name
  s3_object_key_prefix   = local.modeled_routes.music_submission.s3_object_key_prefix
  lambda_function_arn    = local.modeled_routes.music_submission.lambda_function_arn
  lambda_invocation_type = local.modeled_routes.music_submission.lambda_invocation_type
  s3_position            = local.modeled_routes.music_submission.s3_position
  lambda_position        = local.modeled_routes.music_submission.lambda_position
}

# Future identity/DNS module usage remains disabled until existing live SES and
# Cloudflare state has been imported or moved.
# module "parse_domain_identity" {
#   for_each = local.enabled_routes
#
#   source = "github.com/jch254/terraform-modules//ses-domain-identity?ref=1.6.0"
#
#   domain = each.value.parse_domain
#   tags = {
#     Environment = var.environment
#     App         = each.value.app_name
#   }
# }
