FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/app:0.14.4@sha256:d679133fa8b824718f828290bdb1a6353c32989718cc31418a0bb783a20781d9
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
