ARG ALPINE_VERSION=3.24

# Build stage - has apk
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

RUN apk add --no-cache tftp-hpa && \
    mkdir -p /var/tftpboot && chmod 755 /var/tftpboot

# Live stage - minimal
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}

COPY --from=build /usr/sbin/in.tftpd /usr/sbin/
COPY --from=build /var/tftpboot /var/tftpboot

VOLUME /var/tftpboot
EXPOSE 69/udp

# Must run as root (USER 0) to bind port 69/udp on hosts with older kernels.
# Non-root failed (commit 704bbc1, reverted c6988e9). in.tftpd drops privileges after bind.
# droast ignore=DF002
# hadolint ignore=DL3002
USER 0

ENTRYPOINT ["in.tftpd"]
CMD ["--foreground", "--secure", "--ipv4", "/var/tftpboot"]
