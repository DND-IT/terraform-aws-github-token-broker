output "exchange_url" {
  description = "URL consumers call to exchange an OIDC token: <exchange_url>?scope=<owner/repo>&identity=<name>."
  value       = "https://${local.domain}/sts/exchange"
}

output "domain" {
  description = "Audience consumers must request for their OIDC token."
  value       = local.domain
}

output "webhook_url" {
  description = "URL to configure as the GitHub App webhook. Null when the webhook is disabled."
  value       = var.enable_webhook ? "https://${local.domain}/webhook" : null
}

output "kms_key_arn" {
  description = "ARN of the active signing key."
  value       = local.create_keys ? aws_kms_external_key.this[var.active_key_version].arn : var.existing_kms_key_arn
}

output "kms_key_ids" {
  description = "Key ID per key version, as input for scripts/import-key-material.sh."
  value       = { for v, k in aws_kms_external_key.this : v => k.id }
}

output "kms_alias_arn" {
  description = "ARN of the alias the broker signs through. Null when existing_kms_key_arn is set."
  value       = one(aws_kms_alias.this[*].arn)
}

output "broker_role_arn" {
  description = "ARN of the exchange Lambda role."
  value       = aws_iam_role.exchange.arn
}

output "webhook_role_arn" {
  description = "ARN of the webhook Lambda role. Null when the webhook is disabled."
  value       = one(aws_iam_role.webhook[*].arn)
}

output "ecr_repository_urls" {
  description = "URL per function of the ECR repositories created by create_ecr_repositories."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "api_id" {
  description = "ID of the API Gateway HTTP API."
  value       = aws_apigatewayv2_api.this.id
}
