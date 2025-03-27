ARG RUBY_VERSION
FROM ruby:${RUBY_VERSION}

ARG RUNTIME_PACKAGES="catatonit libcurl4"
ENV APP_DIR=/app DEBIAN_FRONTEND=noninteractive

# Create app user
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 -g app -s /bin/bash --create-home app && \
    mkdir -p ${APP_DIR} && \
    chown -R app:app ${APP_DIR}

# Install runtime packages and clean up
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    $RUNTIME_PACKAGES && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_DIR}

ENTRYPOINT ["/usr/bin/catatonit", "--"]
