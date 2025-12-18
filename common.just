# Common variables for Docker image builds
# Import this file in subdirectory Justfiles

# Get previous stable Alpine version (same as CI)
alpine_version := `curl -sq https://dl-cdn.alpinelinux.org/alpine/ | grep ">v" | cut -d 'v' -f 2 | cut -d '/' -f 1 | sort --field-separator=. --version-sort | tail -2 | head -1`

# Get latest stable Ruby version
ruby_version := `curl -s 'https://raw.githubusercontent.com/docker-library/ruby/refs/heads/master/versions.json' | jq -r '[ to_entries[] | select(.value != null and (.key | test("^[0-9]+(\\.[0-9]+)*$"))) | .value.version ] | sort_by(. | split(".") | map(tonumber)) | last'`

# Build Alpine-based image
[private]
_build-alpine image_name:
    docker build --build-arg ALPINE_VERSION={{alpine_version}} -t {{image_name}} .

# Build Ruby-based image
[private]
_build-ruby image_name:
    docker build --build-arg RUBY_VERSION={{ruby_version}}-slim -t {{image_name}} .
