#!/usr/bin/env bash
set -euo pipefail

image_tag="${1:?Usage: $0 <image-tag>}"

test "$(docker run --rm --entrypoint /bin/sh "${image_tag}" -c 'id -u')" = "10001"
docker run --rm --entrypoint borg "${image_tag}" --version
docker run --rm "${image_tag}" --version
docker run --rm --entrypoint ssh "${image_tag}" -V
docker run --rm --entrypoint /bin/sh "${image_tag}" -c 'test -x /bin/sh && /bin/sh -c "exit 0"'
docker run --rm --entrypoint /bin/sh "${image_tag}" -c 'test -w /tmp'
docker run --rm --entrypoint /bin/sh "${image_tag}" -c 'command -v setsid'
! docker run --rm --entrypoint /bin/sh "${image_tag}" -c 'command -v apk'
