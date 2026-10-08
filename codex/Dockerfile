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
        "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-${target}.tar.gz" \
        -o /tmp/codex.tar.gz; \
    tar -xzf /tmp/codex.tar.gz -C /tmp; \
    install -m 755 "/tmp/codex-${target}" /usr/local/bin/codex

FROM debian:trixie-slim

# Package versions intentionally track Debian updates.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates dropbear-bin git openssh-client ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --user-group --shell /bin/bash codex \
    && mkdir -p /home/codex/.ssh /home/codex/.codex /etc/dropbear \
    && chmod 700 /home/codex/.ssh /etc/dropbear \
    && chown -R codex:codex /home/codex /etc/dropbear

COPY --from=download /usr/local/bin/codex /usr/local/bin/codex
ENV HOME=/home/codex

USER 1000:1000
WORKDIR /home/codex
EXPOSE 2222

CMD ["/usr/sbin/dropbear", "-F", "-E", "-R", "-s", "-w", "-p", "2222"]
