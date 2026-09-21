data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  create_keys = var.existing_kms_key_arn == null

  key_deployer_role_arn = coalesce(var.key_deployer_role_arn, data.aws_iam_session_context.current.issuer_arn)

  signer_role_arns = concat(
    [aws_iam_role.exchange.arn],
    aws_iam_role.webhook[*].arn,
  )

  key_arns = local.create_keys ? [for k in aws_kms_external_key.this : k.arn] : [var.existing_kms_key_arn]

  # octo-sts accepts key IDs, key ARNs and alias ARNs alike; signing through
  # the alias makes rotation an alias switch with no function redeploy.
  signing_key_ref = local.create_keys ? aws_kms_alias.this[0].arn : var.existing_kms_key_arn

  domain = coalesce(var.domain_name, trimprefix(aws_apigatewayv2_api.this.api_endpoint, "https://"))

  common_environment = {
    PORT           = "8080"
    KMS_PROVIDER   = "aws"
    KMS_KEYS       = local.signing_key_ref
    GITHUB_APP_IDS = tostring(var.github_app_id)
    METRICS        = "false"
  }
}
