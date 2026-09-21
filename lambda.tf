resource "aws_cloudwatch_log_group" "exchange" {
  name              = "/aws/lambda/${var.name}-exchange"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

resource "aws_lambda_function" "exchange" {
  function_name = "${var.name}-exchange"
  role          = aws_iam_role.exchange.arn
  package_type  = "Image"
  image_uri     = local.exchange_image_uri
  # Upstream publishes linux/amd64 images only.
  architectures = ["x86_64"]
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  environment {
    variables = merge(local.common_environment, {
      STS_DOMAIN = local.domain
    })
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.exchange.name
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy.exchange]
}

resource "aws_lambda_permission" "exchange" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.exchange.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_cloudwatch_log_group" "webhook" {
  count = var.enable_webhook ? 1 : 0

  name              = "/aws/lambda/${var.name}-webhook"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

resource "aws_lambda_function" "webhook" {
  count = var.enable_webhook ? 1 : 0

  function_name = "${var.name}-webhook"
  role          = aws_iam_role.webhook[0].arn
  package_type  = "Image"
  image_uri     = local.webhook_image_uri
  architectures = ["x86_64"]
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  environment {
    variables = merge(local.common_environment, {
      GITHUB_WEBHOOK_SECRET              = var.webhook_secret_arn
      GITHUB_WEBHOOK_ORGANIZATION_FILTER = join(",", var.webhook_organization_filter)
      AWS_LWA_READINESS_CHECK_PATH       = "/healthcheck"
    })
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.webhook[0].name
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy.webhook]
}

resource "aws_lambda_permission" "webhook" {
  count = var.enable_webhook ? 1 : 0

  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
