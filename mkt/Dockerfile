ARG ALPINE_VERSION=3.24

FROM --platform=$BUILDPLATFORM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev AS fetch

# renovate: datasource=github-releases depName=stxkxs/mkt
ARG MKT_VERSION=0.3.0
ARG TARGETARCH

RUN apk add --no-cache ca-certificates curl
WORKDIR /tmp
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN set -eux; \
    archive="mkt_${MKT_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    base="https://github.com/stxkxs/mkt/releases/download/v${MKT_VERSION}"; \
    curl --fail --show-error --silent --location --retry 3 --output "${archive}" "${base}/${archive}"; \
    curl --fail --show-error --silent --location --retry 3 --output checksums.txt "${base}/checksums.txt"; \
    grep " ${archive}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "${archive}" mkt; \
    chmod 0555 mkt

FROM scratch
COPY --from=fetch /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=fetch --chown=0:0 /tmp/mkt /mkt
USER 65532:65532
ENTRYPOINT ["/mkt"]
CMD ["daemon"]
