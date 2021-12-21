ARG ALPINE_VERSION
FROM ghcr.io/zewelor/base:alpine-${ALPINE_VERSION}

RUN apk update \
 && apk upgrade \
 && apk add --no-cache \
            rsync \
            openssh-client \
            ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/cache/apk/*

CMD ["rsync"]
