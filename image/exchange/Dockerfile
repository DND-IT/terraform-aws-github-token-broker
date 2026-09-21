FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/app:0.10.0@sha256:921cd6711ac2ed99f9b12efb2c55372baa0ec4c4facead1eac55dd871e50ffa6
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
