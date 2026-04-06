ARG ALPINE_VERSION

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

# TFTP server must run as root to bind to privileged port 69 (ports < 1024)
# in.tftpd drops privileges internally after binding to the port
# hadolint ignore=DL3002
USER 0

ENTRYPOINT ["in.tftpd"]
CMD ["--foreground", "--secure", "--ipv4", "/var/tftpboot"]
