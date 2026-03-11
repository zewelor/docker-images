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

## CI behavior

CI uses thin path-based workflows to decide what should run and reusable workflows to keep the actual build logic DRY.

- `.github/workflows/image.yml` runs a full rebuild for all images on `workflow_dispatch`, weekly `schedule`, and changes under `.github/workflows/**`.
- `.github/workflows/image-ruby.yml` runs only the Ruby build when `ruby/**` changes, while ignoring Markdown-only and `Justfile`-only changes.
- `.github/workflows/image-rsync.yml`, `.github/workflows/image-sqlite3.yml`, and `.github/workflows/image-tftp.yml` run only the matching Alpine image when that image directory changes, while ignoring Markdown-only and `Justfile`-only changes.
- `.github/workflows/reusable-alpine-version.yml` resolves the previous stable Alpine version once per workflow and exposes it as an output.
- Alpine build workflows first call the reusable Alpine version workflow and then pass that output into the reusable Alpine image build workflow.
- The Alpine lookup command is intentionally kept in one place in CI and mirrored in `common.just` for local builds.
- `.github/workflows/reusable-alpine-image.yml` builds one Alpine image for a pre-resolved Alpine version.
- `.github/workflows/reusable-ruby-image.yml` contains the shared Ruby build, tag, cache, and push logic.

This split exists because GitHub Actions `paths` filtering works at the workflow level, not per job. The small trigger workflows are intentional; they keep change detection simple without duplicating the heavy build steps.

## Adding or changing images

- New Alpine image: add the image directory, add the image name to the matrix in `.github/workflows/image.yml`, and create a thin trigger workflow similar to `.github/workflows/image-rsync.yml`.
- New Ruby-like or otherwise special image: create a dedicated trigger workflow and either reuse an existing reusable workflow or add a new one if the build pattern is genuinely different.
- Keep trigger workflows small: they should mainly define `on: ... paths:` and call a reusable workflow.
- Preserve the doc ignores in path-based workflows so Markdown-only or `Justfile`-only edits do not rebuild images.
- If a CI change affects `.github/workflows/**`, let the full rebuild exercise everything.
