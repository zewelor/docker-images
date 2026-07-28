#!/usr/bin/env bash
set -euo pipefail
image_tag="${1:?Usage: $0 <image-tag>}"

test "$(docker run --rm --entrypoint /bin/busybox "${image_tag}" id -u)" = "100"
docker run --rm --entrypoint /usr/bin/upsc "${image_tag}" -V
