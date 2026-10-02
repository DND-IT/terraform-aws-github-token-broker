FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/app:0.11.1@sha256:6b4f34e7e7e409e947a5c7a78858f82d7f0a2eb246ce5bffb83a9dea3ab6260f
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
