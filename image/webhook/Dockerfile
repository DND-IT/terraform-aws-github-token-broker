FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/webhook:0.13.3@sha256:3c5cce51439cffb5f62848b76354fd92a2691afa6ff1bb8de04f31873f9a70de
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
