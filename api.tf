resource "aws_apigatewayv2_api" "this" {
  name                         = var.name
  protocol_type                = "HTTP"
  disable_execute_api_endpoint = var.domain_name != null

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId         = "$context.requestId"
      requestTime       = "$context.requestTime"
      sourceIp          = "$context.identity.sourceIp"
      routeKey          = "$context.routeKey"
      status            = "$context.status"
      authorizerError   = "$context.authorizer.error"
      integrationError  = "$context.integrationErrorMessage"
      integrationStatus = "$context.integrationStatus"
      subject           = "$context.authorizer.claims.sub"
    })
  }

  tags = var.tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  count = var.enable_jwt_authorizer ? 1 : 0

  api_id           = aws_apigatewayv2_api.this.id
  name             = "oidc"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.jwt_issuer
    audience = concat([local.domain], var.additional_jwt_audiences)
  }
}

resource "aws_apigatewayv2_integration" "exchange" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.exchange.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "exchange" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "GET /sts/exchange"
  target    = "integrations/${aws_apigatewayv2_integration.exchange.id}"

  authorization_type = var.enable_jwt_authorizer ? "JWT" : "NONE"
  authorizer_id      = var.enable_jwt_authorizer ? aws_apigatewayv2_authorizer.jwt[0].id : null
}

resource "aws_apigatewayv2_integration" "webhook" {
  count = var.enable_webhook ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.webhook[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "webhook" {
  count = var.enable_webhook ? 1 : 0

  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /webhook"
  target    = "integrations/${aws_apigatewayv2_integration.webhook[0].id}"
}
