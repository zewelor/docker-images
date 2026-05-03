ARG DHI_DEBIAN_TAG=trixie-debian13

# Build stage - install Neovim and bootstrap the minimal runtime config.
FROM dhi.io/debian-base:${DHI_DEBIAN_TAG}-dev AS build

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    XDG_CONFIG_HOME=/etc/xdg \
    XDG_DATA_HOME=/usr/local/share \
    XDG_STATE_HOME=/tmp/nvim-state

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    fd-find \
    git \
    neovim \
    ripgrep && \
    rm -rf /var/lib/apt/lists/*

COPY config/nvim/ /etc/xdg/nvim/

RUN set -o pipefail && \
    nvim --headless "+Lazy! sync" +qa && \
    find /usr/local/share/nvim/lazy -type d -name '.git' -prune -exec rm -rf {} + && \
    nvim --headless +qa && \
    mkdir -p /runtime-root/usr/bin /runtime-root/usr/libexec /runtime-root/usr/lib /runtime-root/usr/lib/cargo/bin /runtime-root/usr/share /runtime-root/usr/local/share /runtime-root/etc/xdg /runtime-root/lib64 && \
    cp -a /usr/bin/nvim /runtime-root/usr/bin/ && \
    cp -a /usr/bin/git /runtime-root/usr/bin/ && \
    cp -a /usr/bin/rg /runtime-root/usr/bin/ && \
    cp -a /usr/bin/fdfind /runtime-root/usr/bin/ && \
    cp -a /usr/lib/cargo/bin/fd /runtime-root/usr/lib/cargo/bin/ && \
    cp -a /usr/lib/git-core /runtime-root/usr/lib/ && \
    cp -a /usr/libexec/neovim /runtime-root/usr/libexec/ && \
    cp -a /usr/lib/nvim /runtime-root/usr/lib/ && \
    cp -a /usr/share/git-core /runtime-root/usr/share/ && \
    cp -a /usr/share/nvim /runtime-root/usr/share/ && \
    cp -a /usr/local/share/nvim /runtime-root/usr/local/share/ && \
    cp -a /etc/xdg/nvim /runtime-root/etc/xdg/ && \
    : > /tmp/runtime-libs && \
    { printf '%s\n' /usr/bin/nvim /usr/bin/git /usr/bin/rg /usr/bin/fdfind /usr/lib/cargo/bin/fd /usr/libexec/neovim/* /usr/lib/git-core/*; find /usr/lib/nvim -type f -name '*.so'; find /usr/local/share/nvim -type f -name '*.so'; } \
      | while read -r target; do \
        [ -n "$target" ] || continue; \
        ldd "$target" 2>/dev/null | awk '/=> \// {print $3} /^\// {print $1}' >> /tmp/runtime-libs; \
      done && \
    sort -u /tmp/runtime-libs | while read -r lib; do \
      [ -n "$lib" ] || continue; \
      mkdir -p "/runtime-root$(dirname "$lib")"; \
      cp -L "$lib" "/runtime-root$lib"; \
    done && \
    mkdir -p /runtime-root/tmp/nvim-state && \
    chmod 1777 /runtime-root/tmp /runtime-root/tmp/nvim-state

# Runtime stage - keep only Neovim, its runtime deps, and the minimal config.
FROM dhi.io/debian-base:${DHI_DEBIAN_TAG} AS runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV HOME=/tmp \
    XDG_CONFIG_HOME=/etc/xdg \
    XDG_DATA_HOME=/usr/local/share \
    XDG_STATE_HOME=/tmp/nvim-state

WORKDIR /workspace

COPY --from=build /runtime-root/usr/bin/ /usr/bin/
COPY --from=build /runtime-root/usr/libexec/ /usr/libexec/
COPY --from=build /runtime-root/usr/lib/nvim/ /usr/lib/nvim/
COPY --from=build /runtime-root/usr/share/ /usr/share/
COPY --from=build /runtime-root/usr/local/share/ /usr/local/share/
COPY --from=build /runtime-root/etc/xdg/ /etc/xdg/
COPY --from=build /runtime-root/lib/ /lib/
COPY --from=build /runtime-root/lib64/ /lib64/
COPY --from=build /runtime-root/usr/lib/ /usr/lib/

USER 65532:65532

ENTRYPOINT ["nvim"]
CMD ["."]
