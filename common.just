# Common variables for Docker image builds
# Import this file in subdirectory justfiles

# Build Alpine-based image
[private]
_build-alpine image_name:
    docker build --pull -t {{image_name}} .

# Build Ruby-based image
[private]
_build-ruby image_name:
    docker build --pull -t {{image_name}} .

# Build Debian-based image
[private]
_build-debian image_name:
    docker build --pull --build-arg DHI_DEBIAN_TAG=trixie-debian13 -t {{image_name}} .

# Build Debian-based image with local Git identity baked as runtime defaults.
[private]
_build-debian-with-local-git image_name:
    docker build --pull --build-arg DHI_DEBIAN_TAG=trixie-debian13 --build-arg DEFAULT_GIT_USER_NAME="$$(git config --get user.name 2>/dev/null || true)" --build-arg DEFAULT_GIT_USER_EMAIL="$$(git config --get user.email 2>/dev/null || true)" -t {{image_name}} .
