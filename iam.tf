data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exchange" {
  name               = "${var.name}-exchange"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "exchange" {
  statement {
    sid       = "Sign"
    actions   = ["kms:Sign"]
    resources = local.key_arns
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.exchange.arn}:*"]
  }
}

resource "aws_iam_role_policy" "exchange" {
  name   = "broker"
  role   = aws_iam_role.exchange.id
  policy = data.aws_iam_policy_document.exchange.json
}

resource "aws_iam_role" "webhook" {
  count = var.enable_webhook ? 1 : 0

  name               = "${var.name}-webhook"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "webhook" {
  count = var.enable_webhook ? 1 : 0

  statement {
    sid       = "Sign"
    actions   = ["kms:Sign"]
    resources = local.key_arns
  }

  statement {
    sid       = "WebhookSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.webhook_secret_arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.webhook[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "webhook" {
  count = var.enable_webhook ? 1 : 0

  name   = "broker"
  role   = aws_iam_role.webhook[0].id
  policy = data.aws_iam_policy_document.webhook[0].json
}
