ARG ALPINE_VERSION
FROM ghcr.io/zewelor/base:alpine-${ALPINE_VERSION}

USER root
WORKDIR /app

#hadolint ignore=DL3018
RUN \
    apk add --no-cache \
    bash \
    ca-certificates \
    postgresql16-client

COPY ./apps/postgres-init/entrypoint.sh /entrypoint.sh

USER nobody:nogroup

ENTRYPOINT ["dumb-init", "--", "/entrypoint.sh"]

LABEL org.opencontainers.image.source="https://github.com/postgres/postgres"
