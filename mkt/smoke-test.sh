#!/usr/bin/env bash
set -euo pipefail
image_tag="${1:?Usage: $0 <image-tag>}"
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges "${image_tag}" version
