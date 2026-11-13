#!/usr/bin/env bash
set -euo pipefail

image_tag="${1:?Usage: $0 <image-tag>}"

test "$(docker run --rm --network none --entrypoint dpkg-query "${image_tag}" -W '-f=${db:Status-Status}' dumb-init)" = installed
docker run --rm --network none --entrypoint /usr/bin/dumb-init "${image_tag}" --version
docker run --rm "${image_tag}" kubectl version --client
docker run --rm "${image_tag}" jq --version
docker run --rm "${image_tag}" hermes --version
# The gateway must serve the Webapp without building it on the read-only runtime filesystem.
docker run --rm "${image_tag}" test -s /opt/hermes/apps/desktop/dist-webapp/index.html
