provider "aws" {
  region = var.ses_region

  default_tags {
    tags = {
      Environment = var.environment
    }
  }
}

provider "aws" {
  alias  = "platform"
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
    }
  }
}

provider "aws" {
  alias  = "build_notifier"
  region = local.build_notifier_region

  default_tags {
    tags = {
      Environment = var.environment
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  build_notifier_region = coalesce(var.build_notifier_region, var.aws_region)
  cache_bucket_parts    = split("/", var.cache_bucket)
  cache_bucket_name     = local.cache_bucket_parts[0]
  cache_bucket_prefix   = length(local.cache_bucket_parts) > 1 ? join("/", slice(local.cache_bucket_parts, 1, length(local.cache_bucket_parts))) : ""
  cache_bucket_object_arn = local.cache_bucket_prefix != "" ? (
    "arn:aws:s3:::${local.cache_bucket_name}/${local.cache_bucket_prefix}/*"
  ) : "arn:aws:s3:::${local.cache_bucket_name}/*"

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

# Imported-state model: these modules own the live shared SES receipt rule set,
# active selector, and receipt rules.
module "ses_receipt_rule_set" {
  source = "github.com/jch254/terraform-modules//ses-receipt-rule-set?ref=1.15.0"

  name     = "shared-inbound-mail-rules"
  activate = true
}

module "gtd_inbound_rule" {
  source = "github.com/jch254/terraform-modules//ses-receipt-rule?ref=1.15.0"

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
  source = "github.com/jch254/terraform-modules//ses-receipt-rule?ref=1.15.0"

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

module "build_notifier" {
  source = "github.com/jch254/terraform-modules//build-notifier?ref=1.15.0"

  providers = {
    aws = aws.build_notifier
  }

  name               = var.name
  environment        = var.environment
  notification_email = var.build_notification_email
}

module "codebuild_terraform_role" {
  source = "github.com/jch254/terraform-modules//codebuild-terraform-role?ref=1.15.0"

  providers = {
    aws = aws.platform
  }

  name        = var.name
  environment = var.environment
  policy_name = "${var.name}-codebuild"

  cloudwatch_logs_actions = [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
  ]

  s3_read_write_resource_arns = [
    "arn:aws:s3:::${var.remote_state_bucket}",
    "arn:aws:s3:::${var.remote_state_bucket}/*",
  ]

  s3_bucket_arns = ["arn:aws:s3:::${local.cache_bucket_name}"]
  s3_object_arns = [local.cache_bucket_object_arn]

  enable_ses = true

  # SNS/Lambda live in build_notifier_region, which differs from the codebuild role's
  # provider region — pass these explicitly rather than via prefix_managed_services.
  sns_topic_arns = [
    "arn:aws:sns:${local.build_notifier_region}:${data.aws_caller_identity.current.account_id}:${var.name}-*",
  ]

  lambda_function_arns = [
    "arn:aws:lambda:${local.build_notifier_region}:${data.aws_caller_identity.current.account_id}:function:${var.name}-*",
  ]

  prefix_managed_services = ["iam_role"]

  codebuild_project_arns = [
    "arn:aws:codebuild:${var.aws_region}:${data.aws_caller_identity.current.account_id}:project/${var.name}",
  ]

  event_rule_arns = [
    "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/${var.name}-build-notifications",
  ]
}

module "codebuild_project" {
  source = "github.com/jch254/terraform-modules//codebuild-project?ref=1.15.2"

  providers = {
    aws = aws.platform
  }

  name                               = var.name
  description                        = "Deploy shared-platform Terraform"
  codebuild_role_arn                 = module.codebuild_terraform_role.role_arn
  build_compute_type                 = var.build_compute_type
  build_docker_image                 = var.build_docker_image
  build_docker_tag                   = var.build_docker_tag
  privileged_mode                    = false
  image_pull_credentials_type        = "CODEBUILD"
  source_type                        = var.source_type
  source_location                    = var.source_location
  buildspec                          = var.buildspec
  git_clone_depth                    = 1
  cache_bucket                       = var.cache_bucket
  badge_enabled                      = false
  create_log_group                   = false
  webhook_enabled                    = true
  environment                        = var.environment
  build_notifier_lambda_function_arn = module.build_notifier.lambda_function_arn
  build_notifier_github_repo_url     = trimsuffix(var.source_location, ".git")

  environment_variables = [
    { name = "AWS_DEFAULT_REGION", value = var.aws_region },
    { name = "REMOTE_STATE_BUCKET", value = var.remote_state_bucket },
    { name = "TF_STATE_KEY", value = var.remote_state_key },
  ]
}

# Future identity/DNS module usage remains disabled until existing live SES and
# Cloudflare state has been imported or moved.
# module "parse_domain_identity" {
#   for_each = local.enabled_routes
#
#   source = "github.com/jch254/terraform-modules//ses-domain-identity?ref=1.15.0"
#
#   domain = each.value.parse_domain
#   tags = {
#     Environment = var.environment
#     App         = each.value.app_name
#   }
# }
