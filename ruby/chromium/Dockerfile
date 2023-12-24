FROM ghcr.io/zewelor/ruby:3.2.2-slim

# Install runtime packages and clean up
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends chromium xvfb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

