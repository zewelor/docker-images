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
- Keep Docker build contexts minimal with a `.dockerignore` next to every `Dockerfile`

## Developer Thoughts & Architectural Decisions

This repository is built around several core developer priorities designed to maximize developer velocity, security, and repository health:

### 1. Developer Velocity & Zero GHA Overhead
- **Goal**: Adding, removing, or refactoring a Docker image must require **zero** GitHub Actions YAML changes.
- **Why**: Maintaining separate workflow YAMLs for every application leads to maintenance fatigue, drift, and massive code duplication.
- **How**: We implemented dynamic directory discovery (`find`) and paths-filtering (`dorny/paths-filter`) to automatically build a matrix of only the modified applications. Developers only need to focus on their application directories.

### 2. Decoupled, Local-First Testing
- **Goal**: Tests must be decoupled from CI runner environments and easily runnable locally.
- **Why**: Relying solely on GHA to run tests makes troubleshooting slow and frustrating. Hardcoding test commands in YAML files violates the DRY principle.
- **How**: Every application includes an executable `smoke-test.sh` script. GHA dynamically discovers, permissions (`chmod +x`), and executes this script. Developers can run the exact same smoke tests locally.

### 3. Supply Chain Security & Attestations
- **Goal**: All published container images must be securely built and cryptographically verifiable.
- **Why**: Supply chain attacks are a critical risk. Users must be able to verify that the container images published actually originated from this repository.
- **How**: Enforced DHI base images for minimal attack surface, eliminated secrets baking, and integrated **GitHub Actions Build Provenance (Attestations)** to cryptographically sign images during GHA publishing.

### 4. Offline Safety & Local Robustness
- **Goal**: Local development commands (e.g. `just`) must never fail or hang due to network connectivity issues.
- **Why**: Developers frequently work in flaky network or offline environments.
- **How**: All dynamic online lookups (such as Alpine and Ruby version checks in `common.just`) are protected by robust fallback values, allowing offline execution without errors.

## What
Multiarch Docker images (amd64/arm64) for ghcr.io/zewelor. All Alpine-based images use dhi.io base images.

## How

### Build
```bash
cd <image-dir> && just    # build single image
just build-all            # build all images from root
```

### Base images (dhi.io)

Our monorepo adopts Docker Hardened Images (DHI) as primary base images. Key operational rules when developing with DHI images, in accordance with the [Official DHI Migration Guide](https://hub.docker.com/hardened-images/catalog/dhi/build/guides#migrate-to-a-docker-hardened-image):

* **Image Variants & Multi-Stage Builds**:
  * **Build-time (`-dev` suffix)**: Run as `root`, contain a shell, and include package managers (`apk` or `apt`). Use these *only* in build stages to compile binaries and install packages.
  * **Runtime (no suffix)**: Run as the `nonroot` user, contain no package manager, and **no shell**. Copy only the necessary runtime closure (binaries, dynamic libraries) into this clean stage.
* **Non-Root & Permissions**:
  * Ensure files/directories accessed by the application at runtime have appropriate ownership (e.g. `chown -R nonroot` or equivalent permissions) so the `nonroot` user can read/write them.
* **Privileged Port Bindings**:
  * Because runtime containers lack root privileges, they **cannot bind to privileged ports below 1024** (e.g., standard TFTP on port 69). Always configure runtime apps to listen on non-privileged ports (1025 or higher) inside the container, and map them to standard ports externally.
* **Shell-less Runtime & Debugging**:
  * Since production containers lack a shell, traditional `docker exec -it <container> sh` will not work. Use **`docker debug`** to attach an ephemeral troubleshooting environment with interactive shells and tools.
* **CA Certificates**:
  * Root CA certificates are pre-installed in DHI base images. Do not add redundant steps to install certs.


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

**Debian Hardened:** nvim (uses `dhi.io/debian-base`)
- Build stage: `dhi.io/debian-base:<version>-dev`
- Runtime stage: `dhi.io/debian-base:<version>`
- Use for interactive Debian-based tools where copying only the exact runtime closure is not worth the complexity.

### Build context
- Every image directory must contain a `.dockerignore` adjacent to its `Dockerfile`.
- Default to a whitelist-style `.dockerignore` that includes only files needed for the build context.
- For the current images, the build context should stay limited to `Dockerfile` and `.dockerignore`; do not send `justfile`, `README.md`, or other repo files unless the Dockerfile actually needs them.
- If a new image needs local files during `docker build`, explicitly opt those files into `.dockerignore` instead of widening the whole context.

### Catatonit
Only for long-running services: tftp, ruby. Not for CLI tools (sqlite3, rsync) or init containers (postgres-init).

### CI
- `.github/workflows/image.yml` - Central dynamic paths-filtering orchestrator. Automatically detects modified directories (excluding markdown and `justfiles`) on push or pull request, and dynamically constructs a GHA matrix build to test and build ONLY the modified applications. Also handles full rebuilds on schedules, manual dispatches, or workflow file changes.
- `.github/workflows/reusable-alpine-image.yml` - Shared Alpine build logic; automatically discovers and runs directory-level smoke tests.
- `.github/workflows/reusable-ruby-image.yml` - Shared Ruby build logic.
- `.github/workflows/reusable-debian-image.yml` - Shared Debian Hardened build logic; automatically discovers and runs directory-level smoke tests.

### Smoke Testing
- Every application must decouple its smoke test assertions from the GHA workflow files and place them in an executable local `smoke-test.sh` script (e.g. `sqlite3/smoke-test.sh`).
- Smoke test scripts must:
  - Be standard executable shell scripts (using `#!/usr/bin/env bash` and `set -euo pipefail`).
  - Target `test-image:latest` (or `test-image-ruby-base:latest`, etc. for specialized builds).
  - Perform simple validation (e.g. verifying binary execution and outputting `--version`).
- Reusable workflows dynamically detect the presence of `smoke-test.sh` inside the application's directory using `hashFiles`, make it executable, and run it locally during the CI process.

#### CI maintenance rules
- Ensure the central paths filter in `.github/workflows/image.yml` excludes documentation (`*.md`) and local helper recipes (`**/justfile`) to avoid wasteful container builds.
- Do not hardcode testing commands inside GHA workflow YAML files. Keep all test assertions inside the application's local `smoke-test.sh`.

#### Adding a new image
- Create a `.dockerignore` next to `<name>/Dockerfile` keeping the build context minimal.
- Write a `smoke-test.sh` script inside the new image directory to assert basic runtime functionality (e.g. running binary with `--version` flags).
- **Standard Alpine-based Images**: Require **absolutely zero GitHub Actions changes**! The central orchestrator dynamically discovers the new directory containing the `Dockerfile`, passes it to the `reusable-alpine-image.yml` matrix, compiles it, and executes its local `smoke-test.sh` on the fly.
- **Specialized Base Images (Non-Alpine/Debian)**: If adding a non-Alpine image (such as standard ruby or custom debian toolchain), register its specific build routing rules inside `.github/workflows/image.yml` under the matrix/job definitions.


