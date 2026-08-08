#!/usr/bin/env bash
set -euo pipefail

image_tag="${1:?Usage: $0 <image-tag>}"

docker run --rm "${image_tag}" kubectl version --client
docker run --rm "${image_tag}" jq --version
docker run --rm "${image_tag}" hermes --version
