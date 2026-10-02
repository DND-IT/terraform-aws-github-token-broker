variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "github-token-broker"
}

variable "github_app_id" {
  description = "ID of the GitHub App whose private key is imported into the KMS key."
  type        = number
}

variable "additional_github_apps" {
  description = "More GitHub Apps the broker signs for, keyed by a short name. Each gets its own KMS keys, rotated through its key_versions and active_key_version like the primary App's, behind the alias alias/<name>-<key>. octo-sts serves a request with an App installed on the requested owner, so Apps installed on different organizations let one broker serve each organization with its own App."
  type = map(object({
    app_id             = number
    key_versions       = optional(set(string), ["v1"])
    active_key_version = optional(string, "v1")
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.additional_github_apps) : can(regex("^[a-z0-9-]+$", name))])
    error_message = "Keys of additional_github_apps may only contain lowercase letters, digits and hyphens."
  }

  validation {
    condition     = alltrue([for app in values(var.additional_github_apps) : contains(app.key_versions, app.active_key_version)])
    error_message = "Each App's active_key_version must be one of its key_versions."
  }

  validation {
    condition     = length(distinct(concat([var.github_app_id], [for app in values(var.additional_github_apps) : app.app_id]))) == length(var.additional_github_apps) + 1
    error_message = "App IDs must be unique across github_app_id and additional_github_apps."
  }
}

variable "exchange_image_uri" {
  description = "Private ECR image URI (ideally digest-pinned) built from image/exchange/Dockerfile. Required unless create_ecr_repositories is true."
  type        = string
  default     = null

  validation {
    condition     = (var.exchange_image_uri != null) != var.create_ecr_repositories
    error_message = "Set exactly one of exchange_image_uri and create_ecr_repositories."
  }
}

variable "create_ecr_repositories" {
  description = "Create the private ECR repositories the functions run from, and use image_tag in them instead of exchange_image_uri and webhook_image_uri. Lambda cannot use ECR pull through cache, so the images must be copied in, e.g. from GHCR, before the functions can be created."
  type        = bool
  default     = false
}

variable "image_tag" {
  description = "Tag of the images in the repositories created by create_ecr_repositories."
  type        = string
  default     = null

  validation {
    condition     = !var.create_ecr_repositories || var.image_tag != null
    error_message = "image_tag is required when create_ecr_repositories is true."
  }
}

variable "ecr_force_delete" {
  description = "Delete the created ECR repositories even if they still contain images."
  type        = bool
  default     = false
}

variable "enable_webhook" {
  description = "Deploy the octo-sts webhook function, which validates trust policy changes in pull requests."
  type        = bool
  default     = false
}

variable "webhook_image_uri" {
  description = "Private ECR image URI built from image/webhook/Dockerfile. Required when enable_webhook is true, unless create_ecr_repositories is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_webhook || var.create_ecr_repositories || var.webhook_image_uri != null
    error_message = "webhook_image_uri is required when enable_webhook is true and create_ecr_repositories is false."
  }
}

variable "webhook_secret_arn" {
  description = "ARN of a caller-managed Secrets Manager secret holding the GitHub webhook secret. Required when enable_webhook is true. octo-sts reads the webhook secret from Secrets Manager whenever a KMS key is configured."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_webhook || var.webhook_secret_arn != null
    error_message = "webhook_secret_arn is required when enable_webhook is true."
  }
}

variable "webhook_organization_filter" {
  description = "Only process webhook events from these GitHub organizations. Empty processes all."
  type        = list(string)
  default     = []
}

variable "key_versions" {
  description = "One KMS key is created per entry. Add an entry to rotate; remove the old entry once the new key is active."
  type        = set(string)
  default     = ["v1"]
}

variable "active_key_version" {
  description = "Entry of key_versions the alias points at. The broker signs through the alias."
  type        = string
  default     = "v1"

  validation {
    condition     = contains(var.key_versions, var.active_key_version)
    error_message = "active_key_version must be one of key_versions."
  }
}

variable "existing_kms_key_arn" {
  description = "Sign with this pre-existing key instead of creating keys. Its key policy must already allow kms:Sign for the broker role. Meant for ephemeral test deployments that cannot run the import ceremony."
  type        = string
  default     = null
}

variable "key_admin_role_arn" {
  description = "Break-glass role allowed to administer the KMS keys and import key material."
  type        = string
}

variable "key_deployer_role_arn" {
  description = "Role Terraform runs as, granted non-cryptographic key management so it can read and update the keys it creates. Defaults to the role of the current caller."
  type        = string
  default     = null
}

variable "key_reader_role_arns" {
  description = "Roles granted only what Terraform needs to read the keys (kms:DescribeKey, kms:GetKeyPolicy, kms:ListResourceTags), e.g. a read-only role that runs plans on pull requests. The key policy has no account-root statement, so an IAM policy alone cannot grant this."
  type        = list(string)
  default     = []
}

variable "key_deletion_window_in_days" {
  description = "Waiting period before a removed KMS key is deleted."
  type        = number
  default     = 30
}

variable "enable_jwt_authorizer" {
  description = "Put the API Gateway JWT authorizer in front of the exchange route. It restricts callers to jwt_issuer, which is stricter than octo-sts trust policies (they may name any issuer); disable it if non-GitHub-Actions issuers must exchange tokens. The authorizer resource stays either way, detached from the route when off, so the switch is one route update in both directions."
  type        = bool
  default     = true
}

variable "jwt_issuer" {
  description = "Issuer accepted by the JWT authorizer."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "additional_jwt_audiences" {
  description = "Audiences accepted by the JWT authorizer besides the broker domain. octo-sts expects the domain as audience unless a trust policy sets audience or audience_pattern; list those values here."
  type        = list(string)
  default     = []
}

variable "org_policy_repo" {
  description = "Repository, without owner, holding each organization's org-scoped trust policies and its trusted-token-issuers.yaml allowlist (ORG_POLICY_REPO). Applies to every organization the broker serves."
  type        = string
  default     = ".github"

  validation {
    condition     = var.org_policy_repo != ""
    error_message = "org_policy_repo must not be empty."
  }
}

variable "domain_name" {
  description = "Custom domain for the API. When null the API Gateway endpoint is used."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Hosted zone for the domain record and certificate validation. Required when domain_name is set."
  type        = string
  default     = null

  validation {
    condition     = var.domain_name == null || var.route53_zone_id != null
    error_message = "route53_zone_id is required when domain_name is set."
  }
}

variable "lambda_memory_size" {
  description = "Memory for the Lambda functions in MB."
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda functions in seconds. API Gateway caps integrations at 30."
  type        = number
  default     = 30
}

variable "log_retention_in_days" {
  description = "Retention for all CloudWatch log groups."
  type        = number
  default     = 90
}

variable "cloudtrail_log_group_name" {
  description = "CloudWatch log group receiving the account's CloudTrail management events. When null the unexpected-signer alarm is not created."
  type        = string
  default     = null
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic notified when a principal other than the broker roles calls kms:Sign on the key."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
