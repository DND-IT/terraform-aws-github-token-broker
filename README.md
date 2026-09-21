# terraform-aws-github-token-broker

Serverless GitHub App installation token broker: octo-sts on AWS Lambda, with the App private key held in KMS where nobody can read it.

## Overview

Consumer repositories exchange their GitHub Actions OIDC token for a one-hour GitHub App installation token scoped to their own repository and a declared set of permissions. The App private key exists only as non-exportable key material in AWS KMS. No repository, workflow or runner ever holds it.

This replaces the pattern in `DND-IT/github-workflows` where reusable workflows receive `FISSION_GH_APP_PRIVATE_KEY` from the caller and hand it to `actions/create-github-app-token`, which lets every consumer repository dump the key.

The exchange logic is [octo-sts](https://github.com/octo-sts/app), self-hosted and unmodified. This module supplies the AWS side: two Lambda container functions (exchange, and an optional webhook that validates trust policy changes in pull requests) behind an API Gateway HTTP API, the KMS key, tightly scoped IAM, logging and an alarm on unexpected use of the key. The reasoning is recorded in [ADR 0001](docs/adr/0001-github-app-token-broker.md).

### How an exchange works

1. The workflow requests a GitHub OIDC token with the broker `domain` as audience.
2. It calls `GET <exchange_url>?scope=<owner/repo>&identity=<name>` with `Authorization: Bearer <OIDC token>`.
3. The API Gateway JWT authorizer checks issuer, audience and signature.
4. octo-sts loads `.github/chainguard/<name>.sts.yaml` from the default branch of `<owner/repo>`, checks the token against it, signs an App JWT through `kms:Sign`, and asks GitHub for an installation token limited to that repository and the policy's permissions.
5. The response is `{"token": "ghs_..."}`.

A trust policy, committed in the consumer repository:

```yaml
issuer: https://token.actions.githubusercontent.com
subject: repo:DND-IT/my-service:ref:refs/heads/main
permissions:
  contents: write
```

### Lambda adaptation

octo-sts ships two long-running HTTP servers, not Lambda handlers. This module runs the upstream images unchanged and adds the [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) as an extension, which translates Lambda invocations into HTTP requests against the server on `PORT`. Each function is a three-line Dockerfile under [`image/`](image/).

The alternative, a Go `main` of our own importing octo-sts packages behind a Lambda HTTP adapter, would mean copying about 200 lines of upstream wiring (`cmd/app/main.go`: org router, quota store, gRPC gateway) and re-syncing them on every release. The image route needs no code, keeps upstream's cosign-signed binary intact, and both base images are digest-pinned so Renovate bumps them. Its cost: upstream publishes `linux/amd64` only, so the functions run on `x86_64`.

octo-sts is configured through `KMS_PROVIDER=aws`, `KMS_KEYS=<alias ARN>`, `GITHUB_APP_IDS` and `STS_DOMAIN`; it signs with `RSASSA_PKCS1_V1_5_SHA_256` (RS256).

### The JWT authorizer

octo-sts expects the OIDC token audience to equal `STS_DOMAIN` unless a trust policy sets `audience` or `audience_pattern`. The authorizer accepts the same domain, plus anything in `additional_jwt_audiences` for policies that use their own audience. It admits a single issuer (`jwt_issuer`, GitHub Actions by default), which is stricter than octo-sts, whose policies may name any issuer. Set `enable_jwt_authorizer = false` if other issuers must exchange tokens.

## Usage

```hcl
module "github_token_broker" {
  source = "github.com/DND-IT/terraform-aws-github-token-broker?ref=vX.Y.Z"

  github_app_id      = 123456
  exchange_image_uri = "<account>.dkr.ecr.eu-central-1.amazonaws.com/github-token-broker-exchange@sha256:..."
  key_admin_role_arn = "arn:aws:iam::<account>:role/<break-glass>"

  domain_name     = "github-sts.example.com"
  route53_zone_id = "Z..."

  cloudtrail_log_group_name = "<cloudtrail log group>"
  alarm_sns_topic_arn       = "arn:aws:sns:eu-central-1:<account>:<topic>"
}
```

Use a custom domain in production: the domain is the OIDC audience that every consumer requests, and an API Gateway hostname changes if the API is ever recreated.

See [`examples/complete`](examples/complete) for a full deployment including the webhook.

## Development

Prerequisites: Terraform >= 1.10, [tflint](https://github.com/terraform-linters/tflint), [terraform-docs](https://terraform-docs.io/).

```sh
terraform fmt -check -recursive
for d in . examples/complete test/fixture; do
  terraform -chdir=$d init -backend=false -input=false && terraform -chdir=$d validate
done
terraform test
tflint --init && tflint --recursive
terraform-docs .
```

`validate.yaml` runs the same checks on every pull request.

### End-to-end test

`e2e.yaml` deploys `examples/complete` to the DND-IT sandbox account (911453050078, role `cicd-iac`), exchanges the workflow's own OIDC token using the trust policy in [`.github/chainguard/e2e.sts.yaml`](.github/chainguard/e2e.sts.yaml), asserts that the returned token can read this repository and cannot read another, and destroys everything.

A fresh KMS key has no key material, and the PEM must never reach CI, so the run signs with a long-lived key through `existing_kms_key_arn`. One-time setup:

1. Create a test GitHub App owned by DND-IT with repository permissions Contents: read-only and Metadata: read-only, webhook inactive, installable on this account only. octo-sts needs `contents: read` to load the trust policy; an App can never mint a token wider than its own permissions, so this caps what the test key can do. Install it on this repository only and generate a private key.
2. Apply [`test/fixture`](test/fixture) in the sandbox account and import the key with `scripts/import-key-material.sh`.
3. Set the repository variables `BROKER_E2E_APP_ID` and `BROKER_E2E_KMS_KEY_ARN`.

### The e2e trust policy

[`.github/chainguard/e2e.sts.yaml`](.github/chainguard/e2e.sts.yaml) is an ordinary octo-sts trust policy, and doubles as the reference for writing one in a consumer repository. The workflow asks the broker for `scope=DND-IT/terraform-aws-github-token-broker&identity=e2e`; octo-sts maps the identity to the file name (`.github/chainguard/e2e.sts.yaml`) and reads it from the default branch of the scope repository, using a token of its own that is limited to `contents: read` on that one repository.

```yaml
issuer: https://token.actions.githubusercontent.com
subject_pattern: repo:DND-IT/terraform-aws-github-token-broker:(pull_request|ref:refs/heads/main)
claim_pattern:
  workflow_ref: DND-IT/terraform-aws-github-token-broker/\.github/workflows/e2e\.yaml@.*

permissions:
  metadata: read
```

Every condition must hold for the OIDC token the caller presents:

| Field | Checks | Effect here |
|---|---|---|
| `issuer` | `iss` claim, exact match | Only tokens minted by GitHub Actions |
| `subject_pattern` | `sub` claim, regular expression | Only this repository, and only `pull_request` runs or runs on `main`. A push to any other branch, a tag or a GitHub environment produces a different `sub` and is refused |
| `claim_pattern.workflow_ref` | any other claim, regular expression per claim | Only `e2e.yaml`. Another workflow in this repository has a matching `sub` but cannot use this identity |
| audience (not set) | `aud` claim | With no `audience` or `audience_pattern`, octo-sts requires `aud` to equal the broker domain (`STS_DOMAIN`), which is why the workflow requests its OIDC token with the `domain` output as audience. The JWT authorizer enforces the same value first |

Patterns are anchored by octo-sts (`^(?:...)$`), so they match the whole claim; do not add `^` or `$`, and escape literal dots. `subject` and `issuer` have exact-match and `_pattern` forms; use exactly one of each.

`permissions` is what the returned token can do, and nothing else shapes it: the token is an installation token for the scope repository only, carrying exactly these permissions, valid for one hour. A policy cannot grant more than the GitHub App itself holds; asking for more makes GitHub reject the token request. `metadata: read` is enough for the test's assertion (`GET /repos/<this repo>` succeeds, another DND-IT repository returns 404).

Things that surprise people:

- **The policy on `main` is the one in force.** A pull request that edits the policy is still judged by the old one, which is what stops a pull request from granting itself access. It also means a policy change cannot be tested before it is merged.
- **Policies are cached** in memory for five minutes per function instance, including "not found" results. After merging a new or changed policy, an exchange can keep failing for that long.
- **Pull requests from forks** get no OIDC token from GitHub, so they cannot exchange at all. DND-IT repositories are not forked, so this only matters if that changes.
- **The `pull_request` subject covers every pull request in the repository**, whoever opened it. The `workflow_ref` claim pins the workflow file, but on `pull_request` runs that file comes from the pull request's merge commit, so a contributor with push access can edit it. Keep identities that are reachable from pull requests to read-only permissions, as this one is, and give write permissions only to identities restricted to `ref:refs/heads/main` or a protected environment.

## Deployment

The module is consumed from platform Terraform, pinned to a release tag. `release.yaml` runs the `DND-IT/tamci` release action on pushes to `main`, which cuts a `v`-prefixed semantic version and GitHub Release from the Conventional Commit history.

Rolling out a broker:

1. Build and push both images from `image/` to a private ECR repository in the target account (Lambda cannot pull from GHCR). Verify upstream first if you wish: `cosign verify ghcr.io/octo-sts/app@<digest> --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity-regexp 'https://github.com/octo-sts/app/.*'`.
2. Apply the module. The key is created in state `PendingImport`.
3. Run the key import ceremony below.
4. With `enable_webhook = true`: put the webhook secret into the Secrets Manager secret passed as `webhook_secret_arn`, and set the App's webhook URL to the `webhook_url` output.

### Key import ceremony

Performed once per key by a holder of the break-glass role (`key_admin_role_arn`), on a trusted machine with an encrypted disk, OpenSSL 3 and AWS CLI v2.

1. In the GitHub App settings, generate a private key. The browser downloads a PKCS#1 PEM.
2. Run:

   ```sh
   scripts/import-key-material.sh <key id from the kms_key_ids output> ~/Downloads/<app>.private-key.pem
   ```

   The script calls `GetParametersForImport` (`RSA_AES_KEY_WRAP_SHA_256`, the algorithm KMS requires for RSA private keys, with an `RSA_4096` wrapping key), converts the PEM to PKCS#8 DER, wraps it with a one-time AES-256 key (`id-aes256-wrap-pad`) that is itself wrapped with RSA-OAEP-SHA256, calls `ImportKeyMaterial` with `KEY_MATERIAL_DOES_NOT_EXPIRE`, then shreds the PEM and every intermediate file.
3. Confirm the key state printed at the end is `Enabled`, and empty the browser's download history and the trash.

### Rotation

KMS cannot rotate imported key material, so rotation is a new key:

1. Add a version: `key_versions = ["v1", "v2"]`, apply. The alias still targets `v1`.
2. Generate a second private key in the GitHub App settings and import it into the `v2` key with the ceremony above. GitHub accepts both keys.
3. Set `active_key_version = "v2"`, apply. The alias switches; the broker signs through the alias, so no function redeploy is needed.
4. Confirm an exchange succeeds, then delete the old private key in the GitHub App settings.
5. Set `key_versions = ["v2"]`, apply. The old KMS key is scheduled for deletion.

## Ownership

`group:default/dai` (see [`catalog-info.yaml`](catalog-info.yaml)).

## Runbook

| Symptom | Cause | Fix |
|---|---|---|
| Exchange returns 401 with no octo-sts log line | JWT authorizer rejected the token: wrong audience or issuer | Request the OIDC token with the `domain` output as audience; check `authorizerError` in the API access log |
| 403 `trust policy: subject ... did not match` | The policy in the target repository does not match the caller | Fix `.github/chainguard/<identity>.sts.yaml` on the default branch of the target repository |
| 404 / policy not found | No policy for that identity, or the App is not installed on the repository | Add the policy; install the App |
| 5xx with `KMS sign` in the exchange log | Key is `PendingImport`, disabled, or the role lost `kms:Sign` | `aws kms describe-key`; run the import ceremony; check the key policy |
| Function fails at init | Web adapter readiness check failed because octo-sts panicked on configuration | Read the function log; the panic names the environment variable |
| `<name>-unexpected-signer` alarm | A principal other than the broker roles called `kms:Sign` on the key | Treat as an incident: find the caller in CloudTrail, rotate the key |

The alarm reads CloudTrail management events from `cloudtrail_log_group_name`; the trail must not exclude KMS events.

## Follow-ups

Out of scope for this repository's first iteration:

- **Switch `DND-IT/github-workflows` to the broker.** Remove the `app_id` and `app_private_key` inputs from `service-pipeline`, `gh-release` and `gitops-image-tag`, add a broker URL variable, and replace the `actions/create-github-app-token` step with an OIDC exchange step.
- **Org-level trust policy** in the DND-IT `.github` repository, so the reusable workflows use one fixed identity with no per-repository setup.
- **Rotate the current Fission key and restrict the old org secret**, once the broker is live.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.11, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.11, < 7.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_acm_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_apigatewayv2_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api) | resource |
| [aws_apigatewayv2_api_mapping.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api_mapping) | resource |
| [aws_apigatewayv2_authorizer.jwt](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_authorizer) | resource |
| [aws_apigatewayv2_domain_name.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_domain_name) | resource |
| [aws_apigatewayv2_integration.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration) | resource |
| [aws_apigatewayv2_integration.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration) | resource |
| [aws_apigatewayv2_route.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_route.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_stage.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage) | resource |
| [aws_cloudwatch_log_group.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_metric_filter.unexpected_signer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_metric_alarm.unexpected_signer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_external_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_external_key) | resource |
| [aws_lambda_function.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_lambda_permission.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.exchange](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_session_context.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_session_context) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_active_key_version"></a> [active\_key\_version](#input\_active\_key\_version) | Entry of key\_versions the alias points at. The broker signs through the alias. | `string` | `"v1"` | no |
| <a name="input_additional_jwt_audiences"></a> [additional\_jwt\_audiences](#input\_additional\_jwt\_audiences) | Audiences accepted by the JWT authorizer besides the broker domain. octo-sts expects the domain as audience unless a trust policy sets audience or audience\_pattern; list those values here. | `list(string)` | `[]` | no |
| <a name="input_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#input\_alarm\_sns\_topic\_arn) | SNS topic notified when a principal other than the broker roles calls kms:Sign on the key. | `string` | `null` | no |
| <a name="input_cloudtrail_log_group_name"></a> [cloudtrail\_log\_group\_name](#input\_cloudtrail\_log\_group\_name) | CloudWatch log group receiving the account's CloudTrail management events. When null the unexpected-signer alarm is not created. | `string` | `null` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Custom domain for the API. When null the API Gateway endpoint is used. | `string` | `null` | no |
| <a name="input_enable_jwt_authorizer"></a> [enable\_jwt\_authorizer](#input\_enable\_jwt\_authorizer) | Put an API Gateway JWT authorizer in front of the exchange route. It restricts callers to jwt\_issuer, which is stricter than octo-sts trust policies (they may name any issuer); disable it if non-GitHub-Actions issuers must exchange tokens. | `bool` | `true` | no |
| <a name="input_enable_webhook"></a> [enable\_webhook](#input\_enable\_webhook) | Deploy the octo-sts webhook function, which validates trust policy changes in pull requests. | `bool` | `false` | no |
| <a name="input_exchange_image_uri"></a> [exchange\_image\_uri](#input\_exchange\_image\_uri) | Private ECR image URI (ideally digest-pinned) built from image/exchange/Dockerfile. | `string` | n/a | yes |
| <a name="input_existing_kms_key_arn"></a> [existing\_kms\_key\_arn](#input\_existing\_kms\_key\_arn) | Sign with this pre-existing key instead of creating keys. Its key policy must already allow kms:Sign for the broker role. Meant for ephemeral test deployments that cannot run the import ceremony. | `string` | `null` | no |
| <a name="input_github_app_id"></a> [github\_app\_id](#input\_github\_app\_id) | ID of the GitHub App whose private key is imported into the KMS key. | `number` | n/a | yes |
| <a name="input_jwt_issuer"></a> [jwt\_issuer](#input\_jwt\_issuer) | Issuer accepted by the JWT authorizer. | `string` | `"https://token.actions.githubusercontent.com"` | no |
| <a name="input_key_admin_role_arn"></a> [key\_admin\_role\_arn](#input\_key\_admin\_role\_arn) | Break-glass role allowed to administer the KMS keys and import key material. | `string` | n/a | yes |
| <a name="input_key_deletion_window_in_days"></a> [key\_deletion\_window\_in\_days](#input\_key\_deletion\_window\_in\_days) | Waiting period before a removed KMS key is deleted. | `number` | `30` | no |
| <a name="input_key_deployer_role_arn"></a> [key\_deployer\_role\_arn](#input\_key\_deployer\_role\_arn) | Role Terraform runs as, granted non-cryptographic key management so it can read and update the keys it creates. Defaults to the role of the current caller. | `string` | `null` | no |
| <a name="input_key_versions"></a> [key\_versions](#input\_key\_versions) | One KMS key is created per entry. Add an entry to rotate; remove the old entry once the new key is active. | `set(string)` | <pre>[<br/>  "v1"<br/>]</pre> | no |
| <a name="input_lambda_memory_size"></a> [lambda\_memory\_size](#input\_lambda\_memory\_size) | Memory for the Lambda functions in MB. | `number` | `512` | no |
| <a name="input_lambda_timeout"></a> [lambda\_timeout](#input\_lambda\_timeout) | Timeout for the Lambda functions in seconds. API Gateway caps integrations at 30. | `number` | `30` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention for all CloudWatch log groups. | `number` | `90` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for all resources. | `string` | `"github-token-broker"` | no |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Hosted zone for the domain record and certificate validation. Required when domain\_name is set. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources. | `map(string)` | `{}` | no |
| <a name="input_webhook_image_uri"></a> [webhook\_image\_uri](#input\_webhook\_image\_uri) | Private ECR image URI built from image/webhook/Dockerfile. Required when enable\_webhook is true. | `string` | `null` | no |
| <a name="input_webhook_organization_filter"></a> [webhook\_organization\_filter](#input\_webhook\_organization\_filter) | Only process webhook events from these GitHub organizations. Empty processes all. | `list(string)` | `[]` | no |
| <a name="input_webhook_secret_arn"></a> [webhook\_secret\_arn](#input\_webhook\_secret\_arn) | ARN of a caller-managed Secrets Manager secret holding the GitHub webhook secret. Required when enable\_webhook is true. octo-sts reads the webhook secret from Secrets Manager whenever a KMS key is configured. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | ID of the API Gateway HTTP API. |
| <a name="output_broker_role_arn"></a> [broker\_role\_arn](#output\_broker\_role\_arn) | ARN of the exchange Lambda role. |
| <a name="output_domain"></a> [domain](#output\_domain) | Audience consumers must request for their OIDC token. |
| <a name="output_exchange_url"></a> [exchange\_url](#output\_exchange\_url) | URL consumers call to exchange an OIDC token: <exchange\_url>?scope=<owner/repo>&identity=<name>. |
| <a name="output_kms_alias_arn"></a> [kms\_alias\_arn](#output\_kms\_alias\_arn) | ARN of the alias the broker signs through. Null when existing\_kms\_key\_arn is set. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the active signing key. |
| <a name="output_kms_key_ids"></a> [kms\_key\_ids](#output\_kms\_key\_ids) | Key ID per key version, as input for scripts/import-key-material.sh. |
| <a name="output_webhook_role_arn"></a> [webhook\_role\_arn](#output\_webhook\_role\_arn) | ARN of the webhook Lambda role. Null when the webhook is disabled. |
| <a name="output_webhook_url"></a> [webhook\_url](#output\_webhook\_url) | URL to configure as the GitHub App webhook. Null when the webhook is disabled. |
<!-- END_TF_DOCS -->
