# Long-lived signing key for the e2e workflow. Apply once by hand, import a test
# GitHub App key with scripts/import-key-material.sh, and store the key ARN in the
# BROKER_E2E_KMS_KEY_ARN repository variable.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.11, < 7.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

variable "key_admin_role_arn" {
  description = "Role allowed to administer the key and import key material."
  type        = string
}

variable "deployer_role_arn" {
  description = "Role Terraform runs as."
  type        = string
  default     = "arn:aws:iam::911453050078:role/cicd-iac"
}

variable "signer_role_name" {
  description = "Name of the exchange role the e2e run creates."
  type        = string
  default     = "github-app-broker-e2e-exchange"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "key" {
  # The e2e role is deleted and recreated on every run. A role principal would be
  # rewritten to the dead role's unique ID, so match on the ARN through the
  # account principal instead.
  statement {
    sid       = "Sign"
    actions   = ["kms:Sign"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.signer_role_name}"]
    }
  }

  statement {
    sid = "Administration"
    actions = [
      "kms:CancelKeyDeletion",
      "kms:DeleteImportedKeyMaterial",
      "kms:Describe*",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:Get*",
      "kms:ImportKeyMaterial",
      "kms:List*",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [var.key_admin_role_arn, var.deployer_role_arn]
    }
  }
}

resource "aws_kms_external_key" "this" {
  description = "github-app-broker e2e signing key"
  key_spec    = "RSA_2048"
  key_usage   = "SIGN_VERIFY"
  policy      = data.aws_iam_policy_document.key.json
}

output "kms_key_arn" {
  description = "Value for the BROKER_E2E_KMS_KEY_ARN repository variable."
  value       = aws_kms_external_key.this.arn
}

output "kms_key_id" {
  description = "Input for scripts/import-key-material.sh."
  value       = aws_kms_external_key.this.id
}
