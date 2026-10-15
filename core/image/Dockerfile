# Qeet ID Kit image — ghcr.io/qeetgroup/qeet-id-test-kit:<VERSION>
#
# Two jobs, both deterministic and offline at test time:
#   1. `qeet-kit-keygen` generates a profile's test-only secrets (the compose
#      `keygen` service). Nothing is installed at runtime.
#   2. /kit is the kit itself — the payload `update-kit` extracts.
#
# Built by .github/workflows/package.yml with the repository root as the build
# context (.dockerignore limits it to the kit). Bump the openssl pin together with the Alpine base.

FROM public.ecr.aws/docker/library/alpine:3.22.6@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

RUN apk add --no-cache openssl=3.5.9-r0

COPY core/image/keygen.sh /usr/local/bin/qeet-kit-keygen
COPY . /kit
RUN chmod 0755 /usr/local/bin/qeet-kit-keygen

USER 65532:65532
