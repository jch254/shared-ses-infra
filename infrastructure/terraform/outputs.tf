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

output "build_notifier_region" {
  description = "AWS region where the shared CodeBuild notifier is deployed."
  value       = local.build_notifier_region
}

output "build_notification_topic_arn" {
  description = "SNS topic ARN for shared CodeBuild notifications."
  value       = module.build_notifier.sns_topic_arn
}

output "build_notification_lambda_function_arn" {
  description = "Shared CodeBuild notification formatter Lambda function ARN."
  value       = module.build_notifier.lambda_function_arn
}

output "build_notification_lambda_function_name" {
  description = "Shared CodeBuild notification formatter Lambda function name."
  value       = module.build_notifier.lambda_function_name
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project that deploys shared-platform."
  value       = module.codebuild_project.project_name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project that deploys shared-platform."
  value       = module.codebuild_project.project_arn
}

output "build_notification_event_rule_arn" {
  description = "ARN of the shared-platform CodeBuild notification EventBridge rule."
  value       = module.codebuild_project.build_notification_event_rule_arn
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
  description = "Non-secret route contract summary for review before state ownership or live changes."
  value       = local.route_summaries
}

output "receipt_rule_set_name" {
  description = "Name of the active shared SES receipt rule set."
  value       = module.ses_receipt_rule_set.name
}

output "modeled_route_names" {
  description = "Names of the modeled live SES receipt rules."
  value = [
    module.gtd_inbound_rule.name,
    module.music_submission_rule.name,
  ]
}

output "modeled_recipients" {
  description = "Recipients modeled for each live SES route."
  value = {
    gtd_inbound      = local.modeled_routes.gtd_inbound.recipients
    music_submission = local.modeled_routes.music_submission.recipients
  }
}
