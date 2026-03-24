ARG ALPINE_VERSION

# Build stage - has apk
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

RUN apk add --no-cache tftp-hpa && \
    mkdir -p /var/tftpboot && chmod 755 /var/tftpboot

# Live stage - minimal
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}

COPY --from=build /usr/sbin/in.tftpd /usr/sbin/
COPY --from=build /lib/ld-musl-*.so.1 /lib/
COPY --from=build /var/tftpboot /var/tftpboot

VOLUME /var/tftpboot
EXPOSE 69/udp

ENTRYPOINT ["in.tftpd"]
CMD ["-L", "-v", "--secure", "--ipv4", "/var/tftpboot"]
