FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/webhook:0.12.0@sha256:08b8db2d9a7675604154fb379fd83e07ac96ff6926993f1a554e92fd8235f257
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
