#!/bin/sh
set -eu

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

port="${TFTP_PORT:-69}"

exec in.tftpd -L --address ":${port}" --secure --ipv4 /var/tftpboot
