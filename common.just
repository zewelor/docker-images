# Common variables for Docker image builds
# Import this file in subdirectory Justfiles

# Get previous stable Alpine version (same as CI)
alpine_version := `curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 10 https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml | awk '/^  branch: v[0-9]+\.[0-9]+$/ { gsub(/^  branch: v/, "", $0); split($0, v, "."); printf "%s.%d\n", v[1], v[2] - 1; exit }' | grep -E '^[0-9]+\.[0-9]+$'`

# Get latest stable Ruby version
ruby_version := `curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 'https://raw.githubusercontent.com/docker-library/ruby/refs/heads/master/versions.json' | jq -re '[ to_entries[] | select(.value != null and (.key | test("^[0-9]+(\\.[0-9]+)*$"))) | .value.version ] | sort_by(. | split(".") | map(tonumber)) | last'`

# Build Alpine-based image
[private]
_build-alpine image_name:
    docker build --pull --build-arg ALPINE_VERSION={{alpine_version}} -t {{image_name}} .

# Build Ruby-based image
[private]
_build-ruby image_name:
    docker build --pull --build-arg RUBY_VERSION={{ruby_version}}-slim -t {{image_name}} .
