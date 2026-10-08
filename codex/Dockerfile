FROM debian:trixie-slim AS download

# renovate: datasource=github-releases depName=openai/codex extractVersion=^rust-v(?<version>\d+\.\d+\.\d+)$
ARG CODEX_VERSION=0.161.0
ARG TARGETARCH

# Package versions intentionally track Debian updates.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    case "$TARGETARCH" in \
        amd64) target=x86_64-unknown-linux-musl ;; \
        arm64) target=aarch64-unknown-linux-musl ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fLsS --retry 3 \
        "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-package-${target}.tar.gz" \
        -o /tmp/codex.tar.gz; \
    mkdir -p /opt/codex; \
    tar -xzf /tmp/codex.tar.gz -C /opt/codex; \
    rm -rf /opt/codex/codex-resources/voice

FROM debian:trixie-slim

# Package versions intentionally track Debian updates.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates dropbear-bin git openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --user-group --shell /bin/bash codex \
    && mkdir -p /home/codex/.ssh /home/codex/.codex /etc/dropbear \
    && chmod 700 /home/codex/.ssh /etc/dropbear \
    && chown -R codex:codex /home/codex /etc/dropbear \
    && ln -s /opt/codex/bin/codex /usr/local/bin/codex \
    && ln -s /opt/codex/bin/codex-code-mode-host /usr/local/bin/codex-code-mode-host \
    && ln -s /opt/codex/codex-path/rg /usr/local/bin/rg

COPY --from=download /opt/codex /opt/codex
ENV HOME=/home/codex

USER 1000:1000
WORKDIR /home/codex
EXPOSE 2222

CMD ["/usr/sbin/dropbear", "-F", "-E", "-R", "-s", "-w", "-p", "2222"]
