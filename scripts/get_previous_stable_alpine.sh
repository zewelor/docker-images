#!/bin/sh
set -eu

curl -fsSL \
  --retry 5 \
  --retry-all-errors \
  --retry-delay 2 \
  --connect-timeout 10 \
  https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml |
  awk '/^  branch: v[0-9]+\.[0-9]+$/ { gsub(/^  branch: v/, "", $0); split($0, v, "."); printf "%s.%d\n", v[1], v[2] - 1; exit }' |
  grep -E '^[0-9]+\.[0-9]+$'
