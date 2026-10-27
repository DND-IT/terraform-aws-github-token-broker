FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS adapter

FROM ghcr.io/octo-sts/app:0.13.3@sha256:29c7119e693fc2cb35aed3c736277786d2e4a7dedecf42f37084c8fd6168e972
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter
