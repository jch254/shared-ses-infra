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
}

# Future module usage, intentionally disabled until existing live SES state has
# been imported or moved.
#
# terraform-modules tag 1.5.0 includes the first low-risk SES primitives.
#
# module "parse_domain_identity" {
#   for_each = local.enabled_routes
#
#   source = "github.com/jch254/terraform-modules//ses-domain-identity?ref=1.5.0"
#
#   domain = each.value.parse_domain
#   tags = {
#     Environment = var.environment
#     App         = each.value.app_name
#   }
# }
#
# Receipt rule sets, active receipt rule sets, raw mail buckets, and forwarder
# Lambdas are deliberately not scaffolded in this pass. Add those only after the
# live active SES rule set and product-owned resources are fully modelled.
