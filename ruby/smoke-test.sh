#!/usr/bin/env bash
set -euo pipefail

base_image_tag="${1:?Usage: $0 <base-image-tag> <distroless-image-tag>}"
distroless_image_tag="${2:?Usage: $0 <base-image-tag> <distroless-image-tag>}"

docker run --rm "${base_image_tag}" /usr/local/bin/ruby --version
docker run --rm "${distroless_image_tag}" /usr/local/bin/ruby --version
docker run --rm "${base_image_tag}" /usr/local/bin/ruby -e 'abort unless ENV.fetch("BUNDLE_VERSION") == "system"'
docker run --rm "${distroless_image_tag}" /usr/local/bin/ruby -e 'abort unless ENV.fetch("BUNDLE_VERSION") == "system"'

# Load native extensions and their shared libraries in both runtimes.
for image_tag in "${base_image_tag}" "${distroless_image_tag}"; do
    docker run --rm --network none "${image_tag}" /usr/local/bin/ruby -ropenssl -rjson -rpsych -e '
        payload = {"runtime" => "ruby"}
        abort unless OpenSSL::Digest::SHA256.digest("smoke").bytesize == 32
        abort unless JSON.parse(JSON.generate(payload)) == payload
        abort unless Psych.safe_load(Psych.dump(payload)) == payload
    '
done
