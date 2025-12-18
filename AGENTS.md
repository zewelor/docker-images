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
`.github/workflows/image.yml` - builds and pushes to ghcr.io.
