ARG ALPINE_VERSION
FROM ghcr.io/zewelor/base:alpine-${ALPINE_VERSION}

RUN apk add --no-cache tftp-hpa
VOLUME /var/tftpboot
EXPOSE 69/udp

CMD ["in.tftpd", "-L", "--secure","--ipv4","/var/tftpboot"]
