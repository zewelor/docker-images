#!/usr/bin/env bash
set -euo pipefail

base_image_tag="${1:?Usage: $0 <base-image-tag> <distroless-image-tag>}"
distroless_image_tag="${2:?Usage: $0 <base-image-tag> <distroless-image-tag>}"

docker run --rm "${base_image_tag}" /usr/local/bin/ruby --version
docker run --rm "${distroless_image_tag}" /usr/local/bin/ruby --version
