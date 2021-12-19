FROM alpine:3

RUN apk add --no-cache jq curl bind-tools

COPY root /

USER nobody:nogroup

ENTRYPOINT /app/dyndns-updater.sh