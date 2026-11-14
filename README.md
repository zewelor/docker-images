# Monorepo with multiarch docker images
[![Build and push](https://github.com/zewelor/docker-images/actions/workflows/image.yml/badge.svg)](https://github.com/zewelor/docker-images/actions/workflows/image.yml)

This repo intentionally optimizes for simplicity.

[`codex`](codex/README.md) provides a native Codex binary with non-root, key-only SSH
for terminal use and desktop remote connections. Renovate maintains its Dockerfile dependencies as a single twice-monthly group;
see the [Codex update policy](codex/README.md#automatic-updates).

- Package versions are not pinned on purpose.
- Base images and GitHub Actions are not pinned on purpose.
- Alpine-based images track the previous stable Alpine release, not the latest stable release.
- Ruby images track the latest stable Ruby release.
- Images default to root unless a specific image already has a stronger opinion, such as the distroless Ruby variant.
- Alpine runtime images aim to avoid shipping `apk`; `sqlite3`, `tftp`, and `rsync` follow that pattern.
- `tftp` runs as `USER 0` (root) in its runtime image to bind to the standard `69/udp` port, dropping privileges internally after binding.

Because the repo prefers freshness over reproducibility, local builds and CI always pull the latest matching base image tags before building.

## Ruby image workspace

Both Ruby variants default to `/` and provide no `APP_DIR` or `/app` directory.
Derived application Dockerfiles must declare their own `WORKDIR` and directory
ownership. Development containers choose the mounted workspace through Compose
or Dev Container configuration. The slim image retains the `app` user; the
distroless image retains its `nonroot` user.

## CI behavior

CI uses one thin workflow per image, plus one static full rebuild workflow.

- `.github/workflows/image-<name>.yml` - The per-image workflow. It watches that image directory and its own workflow file, ignoring Markdown and image-local `justfile` edits, then calls the appropriate reusable build/publish workflow.
- `.github/workflows/image.yml` - The static full rebuild workflow for manual runs, weekly schedules, and changes to `image.yml`, `reusable-*.yml` or the shared `droast.toml` lint configuration.
- `.github/workflows/reusable-build-image.yml` - The shared lint, smoke, build, tag, publish, and attestation logic for standard Docker images. It relies directly on Dockerfile defaults and publishes latest and sha tags.
- `.github/workflows/reusable-ruby-image.yml` - The shared lint, smoke, build, tag, publish, and attestation logic for Ruby-based images.

Changes to a dedicated `image-<name>.yml` rebuild only its image. Shared workflow changes are handled by the full rebuild instead of triggering every dedicated workflow. A commit changing both shared and image-specific inputs can trigger both paths.

Reusable workflows serialize publication per image across both paths. Active runs
finish; the newest pending run replaces any older pending run. Different images
can still build in parallel, and non-publishing runs use separate locks per ref.

Publishing runs lint and smoke tests before pushing the image with its tags,
then generates GitHub build provenance for the pushed digest. An attestation
failure fails the workflow; the pushed image and tags remain available.
Only runs on `main` publish, including manual runs. Manual runs on other refs
verify the build without publishing. Retry a failed current run normally; to
rebuild after newer commits, start a new manual run from `main` instead of
rerunning a historical run. Serialization does not guarantee commit order for
moving tags such as `latest`.

Ruby's slim SHA tag is `<sha>` and its distroless SHA tag is `<sha>-distroless`.

## Local workflow checks

[pre-commit](.pre-commit-config.yaml) runs actionlint only for staged YAML files
under `.github/workflows/`; unrelated changes are skipped. It installs the pinned
actionlint version in an isolated Go environment, so actionlint does not need a
separate system installation.

Enable the Git hook once per checkout, then check all workflows when needed:

```sh
pre-commit install
pre-commit run actionlint --all-files
```

## Adding or changing images

- **Standard Alpine/Debian-based Images**: To add a new image:
  1. Create the image directory (e.g. `my-app/`).
  2. Add a `Dockerfile` and a `.dockerignore` to keep the build context minimal.
  3. Write a `smoke-test.sh` script (using `#!/usr/bin/env bash` and `set -euo pipefail`) that requires an explicit image tag argument and verifies basic runtime execution (e.g., executing the binary with `--version` flags). Make sure to make it executable locally.
  4. Add a thin `.github/workflows/image-<name>.yml` caller that routes to the right reusable workflow.
- **Specialized/Base Images**: If adding a custom base or non-standard runtime pattern (such as Ruby), keep any special local smoke build setup inside the appropriate reusable workflow instead of duplicating assertions in per-image callers.
