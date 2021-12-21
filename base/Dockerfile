ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache dumb-init

ENTRYPOINT ["dumb-init", "--"]