# Monorepo with multiarch docker images
[![Build and push](https://github.com/zewelor/docker-images/actions/workflows/image.yml/badge.svg)](https://github.com/zewelor/docker-images/actions/workflows/image.yml)

This repo intentionally optimizes for simplicity.

- Package versions are not pinned on purpose.
- Base images and GitHub Actions are not pinned on purpose.
- Alpine-based images track the previous stable Alpine release, not the latest stable release.
- Debian-based images currently track DHI Debian 13.
- Ruby images track the latest stable Ruby release.
- Images default to root unless a specific image already has a stronger opinion, such as the distroless Ruby variant.
- Alpine runtime images aim to avoid shipping `apk`; `sqlite3`, `tftp`, and `rsync` follow that pattern.
- `tftp` runs as `USER 0` (root) in its runtime image to bind to the standard `69/udp` port, dropping privileges internally after binding.

Because the repo prefers freshness over reproducibility, local builds and CI always pull the latest matching base image tags before building.

## CI behavior

CI uses one thin workflow per image, plus one static full rebuild workflow.

- `.github/workflows/image-<name>.yml` - The per-image workflow. It watches only that image directory, ignoring Markdown and `justfile` edits, then calls the appropriate reusable build/publish workflow.
- `.github/workflows/image.yml` - The static full rebuild workflow for manual runs, weekly schedules, and workflow-file changes.
- `.github/workflows/reusable-alpine-image.yml` - The shared lint, smoke, build, tag, publish, and attestation logic for Alpine-based images. It relies directly on Dockerfile defaults and publishes latest and sha tags.
- `.github/workflows/reusable-debian-image.yml` - The shared lint, smoke, build, tag, publish, and attestation logic for Debian-based hardened images.
- `.github/workflows/reusable-ruby-image.yml` - The shared lint, smoke, build, tag, publish, and attestation logic for Ruby-based images.

## Adding or changing images

- **Standard Alpine/Debian-based Images**: To add a new image:
  1. Create the image directory (e.g. `my-app/`).
  2. Add a `Dockerfile` and a `.dockerignore` to keep the build context minimal.
  3. Write a `smoke-test.sh` script (using `#!/usr/bin/env bash` and `set -euo pipefail`) that requires an explicit image tag argument and verifies basic runtime execution (e.g., executing the binary with `--version` flags). Make sure to make it executable locally.
  4. Add a thin `.github/workflows/image-<name>.yml` caller that routes to the right reusable workflow.
- **Specialized/Base Images**: If adding a custom base or non-standard runtime pattern (such as Ruby), keep any special local smoke build setup inside the appropriate reusable workflow instead of duplicating assertions in per-image callers.
