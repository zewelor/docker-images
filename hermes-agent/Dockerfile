# renovate: datasource=docker depName=nousresearch/hermes-agent
ARG HERMES_AGENT_VERSION=v2026.8.18
# renovate: datasource=github-releases depName=jqlang/jq
ARG JQ_VERSION=1.8.2

# Artifact stage - pull multi-arch sourcetap binary from mutable latest package
# hadolint ignore=DL3007
FROM ghcr.io/zewelor/sourcetap:latest AS sourcetap

# Build stage - download and verify kubectl and jq with explicit pipefail
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION} AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG JQ_VERSION

RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    kubectl_version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"; \
    curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${arch}/kubectl"; \
    curl -fsSL -o /tmp/kubectl.sha256 \
        "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${arch}/kubectl.sha256"; \
    echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c; \
    rm /tmp/kubectl.sha256; \
    chmod +x /usr/local/bin/kubectl; \
    if command -v jq >/dev/null 2>&1; then \
        echo "ERROR: Base image already contains jq. Remove custom jq installation from Dockerfile." >&2; \
        exit 1; \
    fi; \
    curl -fsSL -o /usr/local/bin/jq \
        "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${arch}"; \
    curl -fsSL -o /tmp/jq-sha256sum.txt \
        "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/sha256sum.txt"; \
    grep "jq-linux-${arch}\$" /tmp/jq-sha256sum.txt | sed "s|jq-linux-${arch}|/usr/local/bin/jq|" | sha256sum -c; \
    rm /tmp/jq-sha256sum.txt; \
    chmod +x /usr/local/bin/jq; \
    jq --version

# Final stage - copy verified binaries into clean upstream base image
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION}

COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/bin/jq /usr/local/bin/jq
COPY --from=sourcetap /usr/local/bin/sourcetap /usr/local/bin/sourcetap
