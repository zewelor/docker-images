# Monorepo with multiarch docker images
[![Build and push](https://github.com/zewelor/docker-images/actions/workflows/image.yml/badge.svg)](https://github.com/zewelor/docker-images/actions/workflows/image.yml)

This repo intentionally optimizes for simplicity.

- Package versions are not pinned on purpose.
- Base images and GitHub Actions are not pinned on purpose.
- Alpine-based images track the previous stable Alpine release, not the latest stable release.
- Ruby images track the latest stable Ruby release.
- Images default to root unless a specific image already has a stronger opinion, such as the distroless Ruby variant.
- Alpine runtime images aim to avoid shipping `apk`; `sqlite3`, `tftp`, and `rsync` follow that pattern.

Because the repo prefers freshness over reproducibility, local builds and CI always pull the latest matching base image tags before building.
