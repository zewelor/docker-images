#!/usr/bin/env bash
set -euo pipefail

image_tag="${1:?Usage: $0 <image-tag>}"

docker run --rm "${image_tag}" kubectl version --client
docker run --rm "${image_tag}" jq --version
docker run --rm "${image_tag}" sourcetap --help
docker run --rm "${image_tag}" hermes --version
# The gateway must serve the Webapp without building it on the read-only runtime filesystem.
docker run --rm "${image_tag}" test -s /opt/hermes/apps/desktop/dist-webapp/index.html
