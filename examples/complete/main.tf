provider "aws" {
  region = "eu-central-1"
}

locals {
  tags = {
    Repository = "DND-IT/terraform-aws-github-token-broker"
    Example    = "complete"
  }
}

resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"

  tags = local.tags
}

# The value is set out of band so it never enters state:
# aws secretsmanager put-secret-value --secret-id <arn> --secret-string <webhook secret>
resource "aws_secretsmanager_secret" "webhook" {
  name                    = "${var.name}-webhook"
  recovery_window_in_days = 0

  tags = local.tags
}

module "broker" {
  source = "../.."

  name          = var.name
  github_app_id = var.github_app_id

  create_ecr_repositories = true
  image_tag               = var.image_tag
  ecr_force_delete        = true

  enable_webhook     = true
  webhook_secret_arn = aws_secretsmanager_secret.webhook.arn

  webhook_organization_filter = ["DND-IT"]

  key_admin_role_arn   = var.key_admin_role_arn
  existing_kms_key_arn = var.existing_kms_key_arn

  cloudtrail_log_group_name = var.cloudtrail_log_group_name
  alarm_sns_topic_arn       = aws_sns_topic.alarms.arn

  tags = local.tags
}
