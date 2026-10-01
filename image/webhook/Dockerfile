FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/webhook:0.11.1@sha256:55b79c1a86a178f3ed5cb3bb3073b4359fbc9782e62c1fdff446a18c8437a533
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
