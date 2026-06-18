ARG ALPINE_VERSION=3.24

# Build stage - has apk for installing packages and collecting runtime deps
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

ARG ALPINE_VERSION

# renovate: datasource=github-releases depName=transmission/transmission
ARG TRANSMISSION_VERSION=4.1.2

RUN echo "" >> /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community" >> /etc/apk/repositories && \
    apk add --no-cache \
        "transmission-daemon~=${TRANSMISSION_VERSION}" \
        "transmission-remote~=${TRANSMISSION_VERSION}" \
        "transmission-extra~=${TRANSMISSION_VERSION}" \
        ca-certificates \
        pax-utils && \
    mkdir -p /runtime-root/usr/bin /runtime-root/usr/share/transmission /runtime-root/etc && \
    cp -a /usr/bin/transmission-daemon /runtime-root/usr/bin/ && \
    cp -a /usr/bin/transmission-remote /runtime-root/usr/bin/ && \
    cp -a /usr/bin/transmission-create /runtime-root/usr/bin/ && \
    cp -a /usr/bin/transmission-edit /runtime-root/usr/bin/ && \
    cp -a /usr/bin/transmission-show /runtime-root/usr/bin/ && \
    cp -a /usr/share/transmission/public_html /runtime-root/usr/share/transmission/ && \
    cp -a /etc/ssl /runtime-root/etc/ && \
    : > /tmp/runtime-libs && \
    printf '%s\n' \
        /usr/bin/transmission-daemon \
        /usr/bin/transmission-remote \
        /usr/bin/transmission-create \
        /usr/bin/transmission-edit \
        /usr/bin/transmission-show > /tmp/pending-libs && \
    while [ -s /tmp/pending-libs ]; do \
      : > /tmp/new-libs && \
      while read -r target; do \
        [ -n "$target" ] || continue; \
        scanelf --nobanner --needed --format '%n' "$target" | tr ',' '\n' | while read -r soname; do \
          [ -n "$soname" ] || continue; \
          lib=$(find /lib /usr/lib -name "$soname" -print -quit); \
          [ -n "$lib" ] || continue; \
          if ! grep -qxF "$lib" /tmp/runtime-libs; then \
            echo "$lib" >> /tmp/runtime-libs; \
            echo "$lib" >> /tmp/new-libs; \
          fi; \
        done; \
      done < /tmp/pending-libs; \
      cp /tmp/new-libs /tmp/pending-libs; \
    done && \
    sort -u /tmp/runtime-libs | while read -r lib; do \
      mkdir -p "/runtime-root$(dirname "$lib")"; \
      cp -L "$lib" "/runtime-root$lib"; \
    done

# Runtime stage - minimal image without apk
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}

COPY --from=build /runtime-root/usr/bin/ /usr/bin/
COPY --from=build /runtime-root/usr/share/transmission/ /usr/share/transmission/
COPY --from=build /runtime-root/etc/ /etc/
COPY --from=build /runtime-root/lib/ /lib/
COPY --from=build /runtime-root/usr/lib/ /usr/lib/

# hadolint ignore=DL3002
USER 0
RUN mkdir -p /config /downloads /watch && chown -R 65532:65532 /config /downloads /watch
USER 65532

ENV TRANSMISSION_HOME=/config

EXPOSE 9091 51413 51413/udp

ENTRYPOINT ["transmission-daemon"]
CMD ["--foreground"]
