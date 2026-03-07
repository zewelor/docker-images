# Common variables for Docker image builds
# Import this file in subdirectory Justfiles

# Get previous stable Alpine version (same as CI)
alpine_version := `./scripts/get_previous_stable_alpine.sh`

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
