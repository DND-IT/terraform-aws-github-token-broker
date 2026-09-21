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
  value       = module.broker.ecr_repository_urls
}

output "kms_key_ids" {
  description = "Key IDs for the import ceremony."
  value       = module.broker.kms_key_ids
}
