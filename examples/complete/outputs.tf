output "exchange_url" {
  description = "Exchange endpoint."
  value       = module.broker.exchange_url
}

output "domain" {
  description = "Audience for the OIDC token."
  value       = module.broker.domain
}

output "ecr_repository_urls" {
  description = "Repositories the broker images are pushed to."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "kms_key_ids" {
  description = "Key IDs for the import ceremony."
  value       = module.broker.kms_key_ids
}
