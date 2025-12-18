ARG ALPINE_VERSION

# Using -dev image directly (postgresql-client has many deps, multi-stage would be complex)
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev

WORKDIR /app

#hadolint ignore=DL3018
RUN apk add --no-cache bash postgresql16-client

COPY entrypoint.sh /entrypoint.sh

USER nobody:nobody

ENTRYPOINT ["/entrypoint.sh"]

LABEL org.opencontainers.image.source="https://github.com/postgres/postgres"
