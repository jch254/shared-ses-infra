variable "aws_region" {
  description = "Default AWS region used for local/backend-compatible conventions. SES inbound receiving is configured separately via ses_region."
  type        = string
  default     = "ap-southeast-4"
}

variable "ses_region" {
  description = "AWS region for SES inbound receiving."
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "prod"
}

variable "routes" {
  description = "Shared SES inbound route model keyed by stable app route key."
  type = map(object({
    app_name                    = string
    parse_domain                = string
    recipients                  = list(string)
    raw_bucket_name             = string
    raw_object_prefix           = optional(string, "")
    forwarder_lambda_name       = string
    forwarder_lambda_arn        = optional(string)
    parser_endpoint             = string
    parser_secret_parameter_arn = optional(string)
    enabled                     = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for route in var.routes : length(trimspace(route.app_name)) > 0])
    error_message = "Each route must include a non-empty app_name."
  }

  validation {
    condition     = alltrue([for route in var.routes : length(trimspace(route.parse_domain)) > 0])
    error_message = "Each route must include a non-empty parse_domain."
  }

  validation {
    condition     = alltrue([for route in var.routes : length(route.recipients) > 0])
    error_message = "Each route must include at least one recipient domain or address."
  }

  validation {
    condition     = alltrue([for route in var.routes : length(trimspace(route.raw_bucket_name)) > 0])
    error_message = "Each route must include a non-empty raw_bucket_name."
  }

  validation {
    condition     = alltrue([for route in var.routes : length(trimspace(route.forwarder_lambda_name)) > 0])
    error_message = "Each route must include a non-empty forwarder_lambda_name."
  }

  validation {
    condition     = alltrue([for route in var.routes : length(trimspace(route.parser_endpoint)) > 0])
    error_message = "Each route must include a non-empty parser_endpoint."
  }
}
