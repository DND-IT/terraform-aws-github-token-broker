# 0001. GitHub App token broker: octo-sts on Lambda with the key in KMS

**Status:** accepted (2026-09-21)

## Context

The reusable workflows in `DND-IT/github-workflows` take the Fission GitHub App
private key as a caller-supplied secret (`FISSION_GH_APP_PRIVATE_KEY`) and pass it
to `actions/create-github-app-token`. Every consumer repository therefore holds
the key, and any workflow in any of them can print it. The key is org-wide and
long-lived; a leak gives the holder every permission of the App on every
repository it is installed on.

We want consumers to prove who they are with their GitHub Actions OIDC token and
receive a one-hour installation token limited to their own repository and a
declared permission set, with no copy of the key outside one hardened place.

## Options considered

**Where the key lives**

- *Secrets Manager or SSM Parameter Store.* Anything with `GetSecretValue` reads
  the PEM, and the broker holds it in memory. A compromised broker or an
  over-broad IAM policy leaks the key itself, and rotation is the only remedy.
- *KMS asymmetric key with imported material* (`RSA_2048`, `SIGN_VERIFY`, origin
  `EXTERNAL`). The key cannot be exported by anyone, including administrators.
  A compromised broker can sign only while it stays compromised, every signature
  is a CloudTrail event, and access is one `kms:Sign` grant. The cost: KMS cannot
  rotate imported material, so rotation is a manual ceremony.

**What does the exchange**

- *A custom broker.* Full control, but we would own OIDC validation, trust-policy
  evaluation and token scoping: security-critical code to write, review and maintain.
- *octo-sts, self-hosted* (Apache-2.0). Already implements all three, is used in
  production by its authors, has an AWS KMS signer, and works with our existing
  App. Trust policies live in the consumer repository, so access is reviewed where
  it is used.
- *`cruxstack/terraform-aws-octo-sts-serverless`.* Wraps octo-sts for Lambda but
  stores the PEM in SSM and has negligible adoption. Used as a reference only.

**Where it runs**

- *EKS.* We have clusters, but the broker would then depend on the platform that
  its tokens deploy, and a cluster-admin could reach the pod's role.
- *Lambda behind an API Gateway HTTP API.* No dependency on the clusters, scales
  to zero, an isolated IAM role, and a JWT authorizer in front as defence in depth.

**How octo-sts gets onto Lambda**

- *A Go `main` importing octo-sts packages behind a Lambda HTTP adapter.* The
  upstream `cmd/app/main.go` is about 200 lines of router, quota and gRPC-gateway
  wiring that we would copy and keep in step with every release.
- *The upstream image plus the AWS Lambda Web Adapter extension.* A three-line
  Dockerfile per function, no code of ours, upstream's cosign-signed binary
  unchanged. Both base images are digest-pinned and bumped by Renovate.

## Decision

Run self-hosted octo-sts as Lambda container images (upstream image plus Lambda
Web Adapter) behind an API Gateway HTTP API, signing App JWTs with a
non-exportable KMS key that holds imported key material.

## Consequences

- No repository, workflow or runner holds the App key. The PEM exists only during
  the import ceremony.
- Rotation is manual: new key in GitHub, import into a new KMS key, switch the
  alias, delete the old GitHub key. The module's `key_versions` supports the overlap.
- Upstream publishes `linux/amd64` images only, so the functions run on `x86_64`
  rather than the cheaper `arm64`.
- Lambda needs the image in a private ECR repository in the same account, so
  consumers build and push two trivial images.
- Cold starts add latency to the first exchange after idle; every exchange costs
  one `kms:Sign` call.
- With a KMS key configured, the octo-sts webhook reads its webhook secret from
  Secrets Manager. That secret is an HMAC key for webhook deliveries, not the App key.
- Whoever can run Terraform for the key can change its policy. The key policy
  limits this to the deployer role and the break-glass role; an alarm fires on any
  `kms:Sign` by another principal.

## References

- https://github.com/octo-sts/app (v0.10.0: `pkg/kms/aws/aws.go`, `pkg/envconfig/envconfig.go`, `cmd/app/main.go`)
- https://github.com/awslabs/aws-lambda-web-adapter
- https://docs.aws.amazon.com/kms/latest/developerguide/importing-keys-encrypt-key-material.html
- https://github.com/cruxstack/terraform-aws-octo-sts-serverless
