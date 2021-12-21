ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}

RUN apk update \
 && apk upgrade \
 && apk add --no-cache \
            rsync \
            openssh-client \
            ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/cache/apk/*

RUN chmod o+w /run

USER nobody:nogroup

ENTRYPOINT ["rsync"]
