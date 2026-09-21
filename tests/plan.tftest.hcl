mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:sts::111111111111:assumed-role/deployer/session"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::111111111111:role/deployer"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  github_app_id      = 1
  exchange_image_uri = "111111111111.dkr.ecr.eu-central-1.amazonaws.com/exchange:1"
  key_admin_role_arn = "arn:aws:iam::111111111111:role/break-glass"
}

run "defaults" {
  command = plan

  assert {
    condition     = length(aws_kms_external_key.this) == 1
    error_message = "expected exactly one key"
  }

  assert {
    condition     = aws_kms_external_key.this["v1"].key_spec == "RSA_2048" && aws_kms_external_key.this["v1"].key_usage == "SIGN_VERIFY"
    error_message = "key must be RSA_2048 SIGN_VERIFY"
  }

  assert {
    condition     = aws_kms_external_key.this["v1"].key_material_base64 == null
    error_message = "key material must never be managed by Terraform"
  }

  assert {
    condition     = length(aws_lambda_function.webhook) == 0 && length(aws_acm_certificate.this) == 0 && length(aws_cloudwatch_metric_alarm.unexpected_signer) == 0
    error_message = "webhook, domain and alarm must be off by default"
  }

  assert {
    condition     = aws_apigatewayv2_route.exchange.authorization_type == "JWT"
    error_message = "exchange route must sit behind the JWT authorizer by default"
  }
}

run "everything" {
  command = plan

  variables {
    enable_webhook            = true
    webhook_image_uri         = "111111111111.dkr.ecr.eu-central-1.amazonaws.com/webhook:1"
    webhook_secret_arn        = "arn:aws:secretsmanager:eu-central-1:111111111111:secret:webhook"
    key_versions              = ["v1", "v2"]
    active_key_version        = "v2"
    domain_name               = "sts.example.com"
    route53_zone_id           = "Z123"
    cloudtrail_log_group_name = "cloudtrail"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-central-1:111111111111:alarms"
  }

  assert {
    condition     = length(aws_kms_external_key.this) == 2 && length(aws_cloudwatch_log_metric_filter.unexpected_signer) == 2
    error_message = "expected one key and one metric filter per key version"
  }

  assert {
    condition     = aws_lambda_function.exchange.environment[0].variables.STS_DOMAIN == "sts.example.com"
    error_message = "STS_DOMAIN must be the custom domain"
  }

  assert {
    condition     = output.exchange_url == "https://sts.example.com/sts/exchange"
    error_message = "unexpected exchange URL"
  }
}

run "existing_key" {
  command = plan

  variables {
    existing_kms_key_arn = "arn:aws:kms:eu-central-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_kms_external_key.this) == 0 && length(aws_kms_alias.this) == 0
    error_message = "no key or alias may be created when an existing key is supplied"
  }

  assert {
    condition     = aws_lambda_function.exchange.environment[0].variables.KMS_KEYS == var.existing_kms_key_arn
    error_message = "broker must sign with the existing key"
  }
}

run "webhook_requires_inputs" {
  command = plan

  variables {
    enable_webhook = true
  }

  expect_failures = [var.webhook_image_uri, var.webhook_secret_arn]
}
