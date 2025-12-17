ARG ALPINE_VERSION
FROM dhi.io/alpine-base:${ALPINE_VERSION}

RUN apk add --no-cache catatonit

ENTRYPOINT ["catatonit", "--"]
