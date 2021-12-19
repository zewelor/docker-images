ARG ALPINE_VERSION=3
FROM alpine:${ALPINE_VERSION}
RUN apk add --no-cache tftp-hpa
VOLUME /var/tftpboot
EXPOSE 69/udp
ENTRYPOINT ["in.tftpd"]
CMD ["-L", "--secure","--ipv4","/var/tftpboot"]
