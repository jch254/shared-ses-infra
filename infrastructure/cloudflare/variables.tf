variable "cloudflare_api_token" {
  description = "Cloudflare API token with permission to manage DNS records."
  type        = string
  sensitive   = true
  default     = null
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "prod"
}

variable "ses_region" {
  description = "AWS region for SES inbound receiving."
  type        = string
  default     = "ap-southeast-2"
}

variable "zones" {
  description = "Cloudflare zones keyed by a stable zone key."
  type = map(object({
    zone_id = string
    domain  = string
  }))
  default = {}
}

variable "parse_domain_records" {
  description = "Future parse-domain SES DNS model keyed by stable app route key."
  type = map(object({
    zone_key           = string
    parse_domain       = string
    verification_token = optional(string)
    dkim_tokens        = optional(list(string), [])
    mx_name            = string
    mx_priority        = optional(number, 10)
    ttl                = optional(number, 1)
    enabled            = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for record in var.parse_domain_records : contains(keys(var.zones), record.zone_key)])
    error_message = "Each parse_domain_records entry must reference an existing zones key."
  }

  validation {
    condition     = alltrue([for record in var.parse_domain_records : length(trimspace(record.parse_domain)) > 0])
    error_message = "Each parse_domain_records entry must include a non-empty parse_domain."
  }

  validation {
    condition     = alltrue([for record in var.parse_domain_records : length(trimspace(record.mx_name)) > 0])
    error_message = "Each parse_domain_records entry must include a non-empty mx_name."
  }
}
