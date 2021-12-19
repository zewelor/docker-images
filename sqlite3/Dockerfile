ARG ALPINE_VERSION=3
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache sqlite

ENTRYPOINT ["sqlite3"]
