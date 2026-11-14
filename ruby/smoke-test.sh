#!/usr/bin/env bash
set -euo pipefail

base_image_tag="${1:?Usage: $0 <base-image-tag> <distroless-image-tag>}"
distroless_image_tag="${2:?Usage: $0 <base-image-tag> <distroless-image-tag>}"

docker run --rm --network none "${base_image_tag}" /usr/local/bin/ruby --version
docker run --rm --network none "${distroless_image_tag}" /usr/local/bin/ruby --version
docker run --rm --network none "${base_image_tag}" /usr/local/bin/ruby -e 'abort unless ENV.fetch("BUNDLE_VERSION") == "system"'
docker run --rm --network none "${distroless_image_tag}" /usr/local/bin/ruby -e 'abort unless ENV.fetch("BUNDLE_VERSION") == "system"'

# Base images provide the runtime; applications choose their own workspace.
for image_tag in "${base_image_tag}" "${distroless_image_tag}"; do
    docker run --rm --network none "${image_tag}" /usr/local/bin/ruby -e '
        abort "Expected neutral working directory /" unless Dir.pwd == "/"
        abort "Base image must not define APP_DIR" if ENV.key?("APP_DIR")
        abort "Base image must not create /app" if File.exist?("/app")
    '
done

# Load native extensions and their shared libraries in both runtimes.
for image_tag in "${base_image_tag}" "${distroless_image_tag}"; do
    docker run --rm --network none "${image_tag}" /usr/local/bin/ruby -ropenssl -rjson -rpsych -e '
        payload = {"runtime" => "ruby"}
        abort unless OpenSSL::Digest::SHA256.digest("smoke").bytesize == 32
        abort unless JSON.parse(JSON.generate(payload)) == payload
        abort unless Psych.safe_load(Psych.dump(payload)) == payload
    '
done
