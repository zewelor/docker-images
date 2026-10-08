#!/usr/bin/env bash
set -euo pipefail
# Keep auth/errors; the marker drains logs even while SSH children hold stderr open.
exec 3> >(sed -u -E '/^__DROPBEAR_LOG_END__$/Q; / Child connection from /d; / Exit before auth from <[^>]+>: Exited normally$/d' >&2)
filter_pid=$!
/usr/sbin/dropbear "$@" 2>&3 3>&- &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null || true' TERM INT
status=0
wait "$server_pid" || status=$?
if (( status > 128 )); then
    status=0
    wait "$server_pid" || status=$?
fi
printf '%s\n' '__DROPBEAR_LOG_END__' >&3
exec 3>&-
wait "$filter_pid"
exit "$status"
