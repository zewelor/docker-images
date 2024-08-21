ARG RUBY_VERSION
FROM ghcr.io/zewelor/ruby:${RUBY_VERSION}

# Install runtime packages and clean up
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends chromium xvfb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# So it is owned by root and has the permissions vncserver seems to require:
RUN mkdir /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix/
