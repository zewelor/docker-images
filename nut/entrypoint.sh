#!/bin/sh
set -e

# If no arguments are provided, or if the first argument starts with a hyphen,
# run the default startup (driver + daemon).
if [ $# -eq 0 ] || [ "${1#-}" != "$1" ]; then
    echo "Starting NUT driver..."
    /usr/sbin/upsdrvctl -u root start

    echo "Starting NUT daemon..."
    exec /usr/sbin/upsd -u root -D "$@"
fi

# Otherwise, execute the user's custom command (e.g. upsc, sh, etc.)
exec "$@"
