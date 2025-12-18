ARG ALPINE_VERSION

# Build stage - has apk for installing packages
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

RUN apk add --no-cache sqlite

# Live stage - minimal image without apk
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION} AS live

COPY --from=build /usr/bin/sqlite3 /usr/bin/sqlite3
COPY --from=build /usr/lib/libsqlite3.so* /usr/lib/
COPY --from=build /usr/lib/libreadline.so* /usr/lib/
COPY --from=build /usr/lib/libncursesw.so* /usr/lib/

ENTRYPOINT ["sqlite3"]
