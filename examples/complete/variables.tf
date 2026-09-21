variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "github-app-broker-example"
}

variable "github_app_id" {
  description = "ID of the GitHub App."
  type        = number
}

variable "key_admin_role_arn" {
  description = "Break-glass role allowed to administer the KMS key."
  type        = string
}

variable "image_tag" {
  description = "Tag of the images pushed to the ECR repositories this example creates."
  type        = string
  default     = "0.10.0"
}

variable "existing_kms_key_arn" {
  description = "Pre-imported key for ephemeral test runs. Leave null to create the key."
  type        = string
  default     = null
}

variable "cloudtrail_log_group_name" {
  description = "CloudTrail log group for the unexpected-signer alarm."
  type        = string
  default     = null
}
