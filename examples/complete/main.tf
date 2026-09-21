provider "aws" {
  region = "eu-central-1"
}

locals {
  tags = {
    Repository = "DND-IT/terraform-aws-github-token-broker"
    Example    = "complete"
  }
}

resource "aws_ecr_repository" "this" {
  for_each = toset(["exchange", "webhook"])

  name                 = "${var.name}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  tags = local.tags
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

  exchange_image_uri = "${aws_ecr_repository.this["exchange"].repository_url}:${var.image_tag}"

  enable_webhook     = true
  webhook_image_uri  = "${aws_ecr_repository.this["webhook"].repository_url}:${var.image_tag}"
  webhook_secret_arn = aws_secretsmanager_secret.webhook.arn

  webhook_organization_filter = ["DND-IT"]

  key_admin_role_arn   = var.key_admin_role_arn
  existing_kms_key_arn = var.existing_kms_key_arn

  cloudtrail_log_group_name = var.cloudtrail_log_group_name
  alarm_sns_topic_arn       = aws_sns_topic.alarms.arn

  tags = local.tags
}
