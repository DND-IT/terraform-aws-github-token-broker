resource "aws_acm_certificate" "this" {
  count = var.domain_name != null ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  count = var.domain_name != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = one(aws_acm_certificate.this[0].domain_validation_options).resource_record_name
  type    = one(aws_acm_certificate.this[0].domain_validation_options).resource_record_type
  records = [one(aws_acm_certificate.this[0].domain_validation_options).resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  count = var.domain_name != null ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = aws_route53_record.validation[*].fqdn
}

resource "aws_apigatewayv2_domain_name" "this" {
  count = var.domain_name != null ? 1 : 0

  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.this[0].certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = var.domain_name != null ? 1 : 0

  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this[0].id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_route53_record" "this" {
  count = var.domain_name != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
