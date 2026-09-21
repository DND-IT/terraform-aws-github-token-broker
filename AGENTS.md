# terraform-aws-github-app-broker

Terraform module deploying octo-sts on Lambda with the GitHub App key in KMS. Read
`README.md` and `docs/adr/0001-github-app-token-broker.md` first.

## Invariants

- The GitHub App private key must never appear in Terraform state, variables,
  Lambda environment or Secrets Manager. Never set `key_material_base64` on
  `aws_kms_external_key`; material is imported with `scripts/import-key-material.sh`.
- The key policy has no account-root statement on purpose: IAM policies alone
  cannot grant access to the key. Do not add one.
- The JWT authorizer audience and `STS_DOMAIN` must be the same value
  (`local.domain`); octo-sts checks the token audience against `STS_DOMAIN` unless
  a trust policy sets `audience` or `audience_pattern`.
- Upstream octo-sts images are `linux/amd64` only; the functions must stay `x86_64`.
- octo-sts image tags have no `v` prefix (`0.10.0`), while its git tags do (`v0.10.0`).
- octo-sts reads trust policies from the default branch of the target repository,
  so a change to `.github/chainguard/e2e.sts.yaml` only takes effect once merged.

## Validation

Run after every change, from the repo root:

```sh
terraform fmt -check -recursive
for d in . examples/complete test/fixture; do terraform -chdir=$d init -backend=false -input=false && terraform -chdir=$d validate; done
terraform test
tflint --init && tflint --recursive
terraform-docs .
```

## Conventions

- `.yaml` only, never `.yml`. Actions are pinned by commit SHA with a version comment.
- Conventional Commits, signed off. No mention of AI tools in commits, PRs or code.
