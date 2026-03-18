ARG ALPINE_VERSION

# Build stage - has apk
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS build

RUN apk add --no-cache tftp-hpa catatonit

# Live stage - minimal
FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}

COPY --from=build /usr/sbin/in.tftpd /usr/sbin/
COPY --from=build /usr/bin/catatonit /usr/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

USER 0

# Pre-own the served directory so the final non-root runtime can read and write it.
RUN mkdir -p /var/tftpboot && chown 65532:65532 /var/tftpboot && chmod 0755 /usr/local/bin/entrypoint.sh

USER 65532:65532

ENV TFTP_PORT=69

VOLUME /var/tftpboot
EXPOSE 69/udp

ENTRYPOINT ["catatonit", "--", "/usr/local/bin/entrypoint.sh"]
