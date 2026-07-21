# Docker Images Monorepo

This repo builds multiarch Docker images for `ghcr.io/zewelor`. Optimize for simple, obvious maintenance over clever automation or maximum image-size reduction.

## What Matters Here

- Keep each image easy to understand from its own directory.
- Keep build contexts minimal with a `.dockerignore` next to every `Dockerfile`.
- Do not bake secrets into images.
- Prefer fresh upstream packages and base images over pinned reproducibility.
- Preserve local-first workflows: `just` should build images locally, and smoke tests should be executable outside CI.
- Do not make CI routing dynamic. Each image has a thin workflow file; workflow changes are handled by the full rebuild workflow.

## Image Defaults

- Images are multiarch: `linux/amd64` and `linux/arm64`.
- Alpine-based images use Docker Hardened Images from `dhi.io/alpine-base`.
- Debian hardened images use `dhi.io/debian-base`; currently `nvim` uses Debian 13.
- Ruby uses the upstream `ruby:<version>-slim-trixie` base plus a distroless variant on `gcr.io/distroless/base-debian13`.
- The Ruby `RUBY_VERSION` ARG must pin the Debian codename explicitly (e.g. `-slim-trixie`) so it stays aligned with `DISTROLESS_DEBIAN_VERSION`. A bare `-slim` tag is not acceptable: it currently tracks trixie, but the distroless stage must not be allowed to drift when upstream rolls `-slim` to the next stable release. Keep both values on the same Debian major.
- Package versions are intentionally not pinned unless a specific breakage requires it.
- Base image tags live in the Dockerfiles or workflow inputs. Do not reintroduce central version parsing unless there is a clear operational need.
- Images may default to root when that is the practical contract. For example, `tftp` uses root so it can bind `69/udp`.

## Local Builds

Use the repo's `just` entrypoints:

```bash
cd <image-dir> && just
just build-all
```

Image-local `justfile`s should stay thin and import `../common.just`. Put shared local build behavior in `common.just`.

## Dockerfile Style

- Use multi-stage builds when they keep the runtime small without making maintenance painful.
- For DHI images, install packages only in `-dev` build stages when using a minimal runtime stage.
- Copy only the runtime files and shared libraries needed by the final image.
- Use a simpler larger runtime only when dependency copying becomes too fragile or too costly to maintain.
- Add comments only for decisions that are not obvious from the Dockerfile itself.
- Keep `hadolint` ignores narrow and close to the reason.

Current patterns:

- Alpine minimal runtime: `sqlite3`, `tftp`, `rsync`, `nut`.
- Debian hardened runtime: `nvim`.
- Ruby slim plus distroless: `ruby`.

## Build Contexts

Every image directory must have a `.dockerignore`.

Default to whitelist-style contexts:

```dockerignore
*
!Dockerfile
!.dockerignore
```

Only opt in extra files when the Dockerfile actually copies them, such as `nut/entrypoint.sh` or `nvim/config/`.

## Smoke Tests

Every image has an executable `smoke-test.sh` in its image directory.

Rules:

- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Require explicit image tag arguments. Fail if the tag is missing.
- Keep runtime assertions in the script, not in workflow YAML.
- Keep the assertion small: run the binary, print `--version` or equivalent, and fail on non-zero exit.

Reusable workflows build the local test image, call the smoke script with the test tag, and only publish after smoke passes.

## CI Model

CI is intentionally explicit:

- `.github/workflows/image-<name>.yml` watches only that image directory, excluding Markdown and the image-local `justfile`, then calls the right reusable workflow.
- `.github/workflows/image.yml` is the full rebuild workflow. It runs on manual dispatch, weekly schedule, and workflow-file changes.
- Workflow-file changes must not trigger every per-image workflow. They are covered by `image.yml`.
- Reusable workflows own lint, smoke, build, publish, retrying registry login, OCI labels, and build attestations.
- Published images must include GitHub build provenance attestations.

When adding a standard image:

1. Create `<name>/Dockerfile`.
2. Create `<name>/.dockerignore` with a minimal whitelist.
3. Create executable `<name>/smoke-test.sh` with explicit image tag arguments.
4. Add `<name>/justfile` importing `../common.just`.
5. Add a thin `.github/workflows/image-<name>.yml` caller.
6. Add the image to `.github/workflows/image.yml` if it should be included in full rebuilds.

For non-standard image families, add or extend a reusable workflow only when the existing Alpine, Debian, or Ruby reusable workflow does not fit.

## Registry And Publishing

- DHI and GHCR logins should be retried; transient registry failures are expected.
- Do not publish before smoke tests pass.
- Main branch pushes, manual dispatches, and scheduled full rebuilds publish images.
- Pull requests from forks should not run publishing jobs with inherited secrets.

## Maintenance Bias

- Prefer a small amount of explicit YAML over dynamic discovery.
- Prefer one clear pattern per image family over a generic abstraction that hides behavior.
- Avoid broad refactors when touching one image.
- If a change affects shared workflow behavior, run `actionlint` before pushing.
- If CI fails, inspect the exact job logs before changing code. Registry timeouts can be transient; workflow syntax and smoke failures are not.

## Renovate Configuration

When modifying the Renovate configuration (located at `.github/renovate.json`), you **MUST** validate and dry-run the changes locally before committing. This is critical.

### 1. Validate Config Syntax

Run the official Renovate configuration validator:

```bash
npx --yes --package renovate renovate-config-validator
```

### 2. Run Local Dry-Run

To check if Renovate can successfully clone, parse, and extract dependencies using the new configuration, run a dry-run using your GitHub token:

```bash
RENOVATE_TOKEN=$(gh auth token) npx --yes renovate --dry-run=local zewelor/docker-images
```
