FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/webhook:0.14.3@sha256:3c47f6f6455ef8f613727bc182946dc6b3099df15d48f9ce5721d7c65001b3d7
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
