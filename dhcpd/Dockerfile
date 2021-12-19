ARG ALPINE_VERSION=3
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache dhcp

EXPOSE 67/udp 67/tcp

VOLUME /etc/dhcp/dhcpd.conf

RUN ["touch", "/var/lib/dhcp/dhcpd.leases"]

CMD ["/usr/sbin/dhcpd", "-4", "-f", "-d", "--no-pid", "-cf", "/etc/dhcp/dhcpd.conf"]
