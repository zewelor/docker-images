ARG RUBY_VERSION
ARG DISTROLESS_DEBIAN_VERSION=13
FROM ruby:${RUBY_VERSION} AS base

ARG RUNTIME_PACKAGES="catatonit libjemalloc2"
ENV APP_DIR=/app DEBIAN_FRONTEND=noninteractive LD_PRELOAD="libjemalloc.so.2"

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

FROM base AS distroless_builder

# DL4006: pipefail - not needed, we use set -eux and handle errors explicitly
# SC2016: Single quotes intentional - we want literal $ for awk patterns
# hadolint ignore=DL4006,SC2016
RUN set -eux; \
    mkdir -p /distroless-root/usr/local /distroless-root/usr/lib /distroless-root/usr/lib64 /distroless-root/app /distroless-root/usr/bin; \
    cp -a /usr/local/. /distroless-root/usr/local/; \
    cp -a /app/. /distroless-root/app/; \
    cp -a /usr/bin/catatonit /distroless-root/usr/bin/catatonit; \
    # Keep runtime-only Ruby files in distroless image.
    rm -rf /distroless-root/usr/local/include \
    /distroless-root/usr/local/lib/pkgconfig \
    /distroless-root/usr/local/lib/ruby/gems/*/cache \
    /distroless-root/usr/local/lib/ruby/gems/*/doc; \
    find /distroless-root/usr/local/lib/ruby -type f \( -name '*.o' -o -name '*.c' \) -delete; \
    libs_tmp=/tmp/distroless-libs; \
    ldd /usr/local/bin/ruby | awk '/=> \// {print $3} /^\// {print $1}' > "$libs_tmp"; \
    find /usr/local/lib/ruby -name '*.so' -print0 | xargs -0 -r -n1 sh -c 'ldd "$1" || true' sh | awk '/=> \// {print $3} /^\// {print $1}' >> "$libs_tmp"; \
    ldd /usr/bin/catatonit | awk '/=> \// {print $3} /^\// {print $1}' >> "$libs_tmp"; \
    find /usr/lib -name 'libjemalloc.so*' -print0 | xargs -0 -r -n1 sh -c 'ldd "$1" || true' sh | awk '/=> \// {print $3} /^\// {print $1}' >> "$libs_tmp"; \
    find /usr/lib -name 'libjemalloc.so*' >> "$libs_tmp"; \
    sort -u "$libs_tmp" | while read -r lib; do \
    case "$lib" in \
    /usr/lib/*|/usr/local/lib/*) dest="/distroless-root$lib" ;; \
    /lib64/*) dest="/distroless-root/usr/lib64${lib#/lib64}" ;; \
    /lib/*) dest="/distroless-root/usr/lib${lib#/lib}" ;; \
    *) continue ;; \
    esac; \
    mkdir -p "$(dirname "$dest")"; \
    cp -v "$lib" "$dest"; \
    done; \
    chown -R 65532:65532 /distroless-root/app

FROM gcr.io/distroless/base-debian${DISTROLESS_DEBIAN_VERSION}:nonroot AS distroless

ENV APP_DIR=/app \
    HOME=/home/nonroot \
    BUNDLE_USER_HOME=/tmp/bundler \
    BUNDLE_USER_CACHE=/tmp/bundler/cache \
    BUNDLE_USER_PLUGIN=/tmp/bundler/plugin \
    LD_PRELOAD="libjemalloc.so.2"

WORKDIR ${APP_DIR}

COPY --from=distroless_builder /distroless-root/usr/local/ /usr/local/
COPY --from=distroless_builder /distroless-root/usr/lib/ /usr/lib/
COPY --from=distroless_builder /distroless-root/usr/lib64/ /usr/lib64/
COPY --from=distroless_builder /distroless-root/app/ /app/
COPY --from=distroless_builder /distroless-root/usr/bin/catatonit /usr/bin/catatonit

USER nonroot

ENTRYPOINT ["/usr/bin/catatonit", "--"]
