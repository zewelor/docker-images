ARG ALPINE_VERSION

# Using -dev image directly (ssh has complex OpenSSL dependencies)
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev

RUN apk add --no-cache rsync openssh-client ca-certificates

CMD ["rsync"]
