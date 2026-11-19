FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/webhook:0.14.4@sha256:04b595111ed3b7787b5053b41cfe2efbd2ee0cc419ff930cdd882de162ce3e5a
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
