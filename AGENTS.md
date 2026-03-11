# Docker Images Monorepo

## Goals

### Security
- Minimal attack surface via multi-stage builds where practical
- No secrets baked into images
- Users can run with `--user` flag if needed (images default to root for flexibility)

### Simplicity
- Prefer maintainability over smaller image size
- One clear pattern per use case (multi-stage vs single-stage)
- Document trade-offs in comments

### Maintainability
- DRY: common.just for shared build logic
- CI adds OCI labels automatically
- Self-explanatory Dockerfile comments

## What
Multiarch Docker images (amd64/arm64) for ghcr.io/zewelor. All Alpine-based images use dhi.io base images.

## How

### Build
```bash
cd <image-dir> && just    # build single image
just build-all            # build all images from root
```

### Base images (dhi.io)
- `-dev` suffix: has apk (for installing packages)
- no suffix: minimal, no apk

### Image patterns

**Multi-stage (simple binaries):** sqlite3, tftp
- Build stage: install packages in `-dev`
- Live stage: copy only needed binaries/libs to minimal
- See `sqlite3/Dockerfile`, `tftp/Dockerfile`

**Single-stage -dev (complex deps):** rsync, postgres-init
- When package has many shared lib dependencies (OpenSSL, etc.)
- Simpler to maintain, larger image
- See `rsync/Dockerfile`

**Non-Alpine:** ruby (uses ruby:slim)

### Catatonit
Only for long-running services: tftp, ruby. Not for CLI tools (sqlite3, rsync) or init containers (postgres-init).

### CI
- `.github/workflows/image.yml` - full rebuild for all images on workflow changes, manual dispatch, and schedule.
- `.github/workflows/image-ruby.yml` - Ruby-only trigger workflow.
- `.github/workflows/image-rsync.yml`, `.github/workflows/image-sqlite3.yml`, `.github/workflows/image-tftp.yml` - per-image Alpine trigger workflows.
- `.github/workflows/image-alpine-shared.yml` - rebuilds all Alpine images when the shared Alpine version lookup script changes.
- `.github/workflows/reusable-alpine-image.yml` - shared Alpine build logic.
- `.github/workflows/reusable-ruby-image.yml` - shared Ruby build logic.

#### CI maintenance rules
- Keep path-based trigger workflows thin. They should mostly define `paths` filters and call a reusable workflow.
- Use `paths` and `paths-ignore` style exclusions to avoid rebuilds for docs-only changes where practical.
- For per-image workflows, ignore Markdown-only and `Justfile`-only changes unless those files start affecting build behavior.
- If a change affects only one image directory, only that image's workflow should run.
- If a change affects shared Alpine CI logic, rebuild all Alpine images.
- If a change affects `.github/workflows/**`, rebuild all images so workflow changes are exercised immediately.

#### Adding a new image
- If it follows the Alpine pattern, reuse `.github/workflows/reusable-alpine-image.yml`.
- Add the image name to the Alpine matrix in `.github/workflows/image.yml`.
- Add the image name to `.github/workflows/image-alpine-shared.yml` so shared Alpine helper changes rebuild it too.
- Create a thin trigger workflow named `.github/workflows/image-<name>.yml` modeled after the existing per-image workflows.
- Include path filters for `<name>/**` and exclude Markdown and `Justfile` changes unless that image needs different rules.

#### Changing CI
- Prefer changing reusable workflows before copying steps into trigger workflows.
- Keep full rebuild logic centralized in `.github/workflows/image.yml`.
- After CI changes, validate YAML locally and check the pushed GitHub Actions runs to confirm the intended workflows triggered.
