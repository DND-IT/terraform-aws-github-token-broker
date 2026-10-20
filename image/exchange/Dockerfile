FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/app:0.12.0@sha256:c035da62267fa4e9fd5134eaae41ce0397b68ae13e6daf0f5f6d70d2a81e5d69
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
