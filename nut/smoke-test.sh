#!/usr/bin/env bash
set -euo pipefail
docker run --rm --entrypoint /usr/bin/upsc test-image:latest -V
