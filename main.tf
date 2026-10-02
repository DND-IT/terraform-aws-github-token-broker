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

  additional_key_versions = merge([
    for name, app in var.additional_github_apps : {
      for version in app.key_versions : "${name}/${version}" => { app = name, version = version }
    }
  ]...)

  key_arns = concat(
    local.create_keys ? [for k in aws_kms_external_key.this : k.arn] : [var.existing_kms_key_arn],
    [for k in aws_kms_external_key.additional : k.arn],
  )

  # octo-sts accepts key IDs, key ARNs and alias ARNs alike; signing through
  # the alias makes rotation an alias switch with no function redeploy.
  signing_key_ref = local.create_keys ? aws_kms_alias.this[0].arn : var.existing_kms_key_arn

  # octo-sts pairs GITHUB_APP_IDS and KMS_KEYS by position.
  additional_app_names = sort(keys(var.additional_github_apps))
  app_ids              = concat([var.github_app_id], [for name in local.additional_app_names : var.additional_github_apps[name].app_id])
  signing_key_refs     = concat([local.signing_key_ref], [for name in local.additional_app_names : aws_kms_alias.additional[name].arn])

  domain = coalesce(var.domain_name, trimprefix(aws_apigatewayv2_api.this.api_endpoint, "https://"))

  common_environment = {
    PORT            = "8080"
    KMS_PROVIDER    = "aws"
    KMS_KEYS        = join(",", local.signing_key_refs)
    GITHUB_APP_IDS  = join(",", local.app_ids)
    METRICS         = "false"
    ORG_POLICY_REPO = var.org_policy_repo
  }
}
