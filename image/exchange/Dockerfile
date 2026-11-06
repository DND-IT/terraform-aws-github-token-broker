FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/app:0.14.3@sha256:cb91dd3e7adbf15f9cacb8dd0f718fbc39eef038604869f53e011062747314f1
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
