#!/usr/bin/env bash
set -euo pipefail
image_tag="${1:?Usage: $0 <image-tag>}"
docker run --rm --entrypoint /usr/bin/upsc "${image_tag}" -V
