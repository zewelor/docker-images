#!/bin/sh
set -e

echo "Starting NUT driver..."
/usr/sbin/upsdrvctl -u nut start

echo "Starting NUT daemon..."
exec /usr/sbin/upsd -u nut -D "$@"
