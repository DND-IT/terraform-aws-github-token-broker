FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/webhook:0.10.0@sha256:e10b2840321d548cd965bf6e39066e823e21c444c04d6a2655a600811c848c0e
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
