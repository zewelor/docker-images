#!/bin/sh
set -e

echo "Starting NUT driver..."
/usr/sbin/upsdrvctl -u root start

echo "Starting NUT daemon..."
exec /usr/sbin/upsd -u root -D "$@"
