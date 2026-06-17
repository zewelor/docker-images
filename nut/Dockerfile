ARG ALPINE_VERSION=3.24

# Build stage - has apk for installing packages and collecting runtime deps
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Install nut and dependencies, then build the minimal runtime root
RUN apk add --no-cache nut pax-utils && \
    mkdir -p /runtime-root/usr/sbin \
             /runtime-root/usr/bin \
             /runtime-root/usr/lib/nut \
             /runtime-root/lib \
             /runtime-root/etc/nut \
             /runtime-root/run/nut \
             /runtime-root/var/db/nut \
             /runtime-root/bin \
             /runtime-root/sbin && \
    cp -a /usr/sbin/upsd /runtime-root/usr/sbin/ && \
    cp -a /usr/sbin/upsdrvctl /runtime-root/usr/sbin/ && \
    cp -a /usr/bin/upsc /runtime-root/usr/bin/ && \
    cp -a /usr/bin/upscmd /runtime-root/usr/bin/ && \
    cp -a /usr/lib/nut/. /runtime-root/usr/lib/nut/ && \
    cp -a /etc/nut/. /runtime-root/etc/nut/ && \
    cp -a /bin/busybox /runtime-root/bin/busybox && \
    ln -sf /bin/busybox /runtime-root/bin/sh && \
    ln -sf /bin/busybox /runtime-root/bin/ash && \
    ln -sf /usr/sbin/upsd /runtime-root/sbin/upsd && \
    ln -sf /usr/sbin/upsdrvctl /runtime-root/sbin/upsdrvctl && \
    # Ensure directories have proper permissions
    chown -R 0:0 /runtime-root && \
    chmod 755 /runtime-root/run/nut && \
    chmod 755 /runtime-root/var/db/nut && \
    echo "root:x:0:0:root:/root:/bin/sh" > /runtime-root/etc/passwd && \
    echo "root:x:0:" > /runtime-root/etc/group && \
    echo "nut:x:100:101:nut:/var/db/nut:/sbin/nologin" >> /runtime-root/etc/passwd && \
    echo "nut:x:101:nut" >> /runtime-root/etc/group && \
    # Trace shared libraries dependencies dynamically
    : > /tmp/runtime-libs && \
    printf '%s\n' /usr/sbin/upsd /usr/sbin/upsdrvctl /usr/bin/upsc /usr/bin/upscmd /bin/busybox > /tmp/pending-libs && \
    find /usr/lib/nut -type f >> /tmp/pending-libs && \
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

# Copy entrypoint script
COPY entrypoint.sh /runtime-root/entrypoint.sh
RUN chmod +x /runtime-root/entrypoint.sh

# Runtime stage - minimal image without apk
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}

COPY --from=build /runtime-root/ /

EXPOSE 3493

# Run as root in container to allow libusb to access mapped USB device nodes without privileged=true
# hadolint ignore=DL3002
USER 0

ENTRYPOINT ["/entrypoint.sh"]
