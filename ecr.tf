locals {
  ecr_repositories = var.create_ecr_repositories ? toset(var.enable_webhook ? ["exchange", "webhook"] : ["exchange"]) : toset([])

  exchange_image_uri = var.create_ecr_repositories ? "${aws_ecr_repository.this["exchange"].repository_url}:${var.image_tag}" : var.exchange_image_uri
  webhook_image_uri  = var.create_ecr_repositories && var.enable_webhook ? "${aws_ecr_repository.this["webhook"].repository_url}:${var.image_tag}" : var.webhook_image_uri
}

resource "aws_ecr_repository" "this" {
  for_each = local.ecr_repositories

  name                 = "${var.name}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}
