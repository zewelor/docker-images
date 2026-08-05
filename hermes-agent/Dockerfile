ARG HERMES_AGENT_VERSION=v2026.8.3

# Build stage - download and verify kubectl with explicit pipefail
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION} AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

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
    kubectl version --client

# Final stage - copy verified kubectl into clean upstream base image
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION}

COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
