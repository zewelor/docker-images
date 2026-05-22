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

CI uses a modernized, zero-overhead dynamic orchestration pattern designed for developer velocity, offline safety, and decoupled testing.

- `.github/workflows/image.yml` - The central orchestrator. It uses `dorny/paths-filter` to dynamically detect modified image directories (ignoring Markdown and `justfile` edits) on pushes or pull requests. It automatically constructs a GHA matrix to build and test *only* the affected images. It also manages full multi-platform rebuilds on weekly schedules, manual dispatches, or workflow file changes.
- `.github/workflows/reusable-alpine-image.yml` - The shared build, tag, and publish logic for Alpine-based images. It dynamically parses the `ARG ALPINE_VERSION` directly from the application's `Dockerfile` as the source of truth, and runs the application's localized smoke-test suite.
- `.github/workflows/reusable-debian-image.yml` - The shared build, tag, and publish logic for Debian-based hardened images, running localized smoke-test suites.
- `.github/workflows/reusable-ruby-image.yml` - The shared build, tag, and publish logic for Ruby-based images.

## Adding or changing images

- **Standard Alpine/Debian-based Images**: Require **absolutely zero GitHub Actions changes**! To add a new image:
  1. Create the image directory (e.g. `my-app/`).
  2. Add a `Dockerfile` and a `.dockerignore` to keep the build context minimal.
  3. Write a `smoke-test.sh` script (using `#!/usr/bin/env bash` and `set -euo pipefail`) that targets `test-image:latest` and verifies basic runtime execution (e.g., executing the binary with `--version` flags). Make sure to make it executable locally.
  4. The central orchestrator will automatically discover your folder, resolve the correct reusable workflow, compile the multiarch image, and run your `smoke-test.sh` on the fly.
- **Specialized/Base Images**: If adding a custom base or non-standard runtime pattern (such as Ruby), register its specific build routing rules under the central orchestrator (`image.yml`) matrix or job definitions.

