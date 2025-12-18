ARG ALPINE_VERSION

# Build stage - has apk
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

RUN apk add --no-cache tftp-hpa catatonit

# Live stage - minimal
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}

COPY --from=build /usr/sbin/in.tftpd /usr/sbin/
COPY --from=build /usr/bin/catatonit /usr/bin/

VOLUME /var/tftpboot
EXPOSE 69/udp

ENTRYPOINT ["catatonit", "--"]
CMD ["in.tftpd", "-L", "--secure", "--ipv4", "/var/tftpboot"]
