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

# Build standard Docker image
[private]
_build-standard image_name:
    docker build --pull -t {{image_name}} .

test_dockerignore:
    #!/bin/sh
    set -eu
    LC_ALL=C
    export LC_ALL

    test_dir="$(mktemp -d)"
    trap 'rm -rf "$test_dir"' 0 1 2 3 15
    mkdir -p "$test_dir/context"

    docker build --file - --progress=quiet --output "type=local,dest=$test_dir/context" . >/dev/null <<-'EOF'
    # syntax=docker/dockerfile:1
    #check=skip=CopyIgnoredFile
    FROM scratch
    COPY . /context
    EOF

    find "$test_dir/context/context" -type f -print |
        sed "s#^$test_dir/context/context/##" |
        sort > "$test_dir/included"

    cat "$test_dir/included"
    printf '\n%s\n' '---'
    printf 'Total files:\t%s\n' "$(wc -l < "$test_dir/included" | awk '{print $1}')"
    printf 'Total size:\t%s\n' "$(du -sh "$test_dir/context/context" | awk '{print $1}')"

