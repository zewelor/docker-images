ARG ALPINE_VERSION

# Build stage - has apk for installing packages and collecting runtime deps
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache rsync openssh-client ca-certificates pax-utils && \
    mkdir -p /runtime-root/usr/bin /runtime-root/usr/lib /runtime-root/lib /runtime-root/etc && \
    cp -a /usr/bin/rsync /runtime-root/usr/bin/ && \
    cp -a /usr/bin/ssh /runtime-root/usr/bin/ && \
    cp -a /etc/ssl /runtime-root/etc/ && \
    cp -a /etc/ssh /runtime-root/etc/ && \
    # Add root user for rsync daemon compatibility (rsync needs named users in config) \
    echo "root:x:0:0:root:/root:/bin/sh" > /runtime-root/etc/passwd && \
    : > /tmp/runtime-libs && \
    printf '%s\n' /usr/bin/rsync /usr/bin/ssh > /tmp/pending-libs && \
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

# Runtime stage - minimal image without apk, defaulting to nonroot
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}

COPY --from=build /runtime-root/usr/bin/ /usr/bin/
COPY --from=build /runtime-root/etc/ /etc/
COPY --from=build /runtime-root/lib/ /lib/
COPY --from=build /runtime-root/usr/lib/ /usr/lib/

# hadolint ignore=DL3002
USER 0

ENTRYPOINT ["rsync"]
CMD ["--help"]
