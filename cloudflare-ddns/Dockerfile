ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache jq curl bind-tools

COPY root /

USER nobody:nogroup

ENTRYPOINT /app/dyndns-updater.sh