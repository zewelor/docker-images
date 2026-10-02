# mkt

Minimal multiarch image for [stxkxs/mkt](https://github.com/stxkxs/mkt).
The Dockerfile selects the release; the fetch stage verifies the archive against
its release checksum. The final `scratch` image contains only `/mkt` and the CA
bundle, and runs as `65532:65532`. The default command is `daemon`.

## Local build and smoke test

```bash
cd ~/personal/docker-images/mkt && just
./smoke-test.sh mkt
```

## Publication through GitHub Actions

The thin `image-mkt.yml` caller uses the existing `reusable-build-image.yml`.
After Dockerfile lint and the smoke test, trusted main pushes publish amd64/arm64
images with `latest`, the source commit and the `MKT_VERSION` tag. The existing
full-rebuild workflow also includes mkt. Publishing uses `GITHUB_TOKEN` with
`packages: write` and generates GitHub build provenance attestations.

To rebuild explicitly:

```bash
gh workflow run image-mkt.yml --repo zewelor/docker-images --ref main
```

Pin the published multiarch index digest in the GitOps chart. The registry tag
and workflow attestations must match the source revision before deployment.

## Runtime

Set `MKT_CONFIG_DIR=/config` and provide a writable directory owned by UID 65532.
Seed `config.yaml` before startup; an absent file seeds upstream example data.
All history is kept in the same directory. HTTPS/WSS access is required for Yahoo
and Coinbase. No HTTP listener is enabled by default.
