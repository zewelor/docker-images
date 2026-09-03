ARG ALPINE_VERSION=3.24

FROM dhi.io/alpine-base:${ALPINE_VERSION}-alpine${ALPINE_VERSION}-dev
ARG ALPINE_VERSION

# droast ignore=DF057
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community \
        borgbackup \
        borgmatic \
        openssh-client \
        ca-certificates && \
    addgroup -g 10001 borgmatic && \
    adduser -u 10001 -G borgmatic -D -h /borg -s /bin/sh borgmatic && \
    rm -rf /sbin/apk /etc/apk /lib/apk /var/cache/apk/* && \
    rm -f /usr/bin/scp /usr/bin/sftp /usr/bin/ssh-add /usr/bin/ssh-agent /usr/bin/ssh-keygen /usr/bin/ssh-keyscan /usr/bin/borgfs && \
    rm -rf /usr/share/man /usr/share/doc /usr/share/info /usr/include && \
    mkdir -p /borg /tmp && \
    chown -R 10001:10001 /borg && \
    chmod 1777 /tmp
ENV HOME=/borg \
    BORG_CACHE_DIR=/borg/cache \
    BORG_CONFIG_DIR=/borg/config \
    BORG_SECURITY_DIR=/borg/security \
    XDG_CACHE_HOME=/borg/cache \
    XDG_CONFIG_HOME=/borg/config \
    XDG_STATE_HOME=/borg/state
# Must run as root (USER 0) for mounted backup source volume access across heterogeneous file owners.
# droast ignore=DF002
# hadolint ignore=DL3002
USER 0

ENTRYPOINT ["borgmatic"]
CMD ["--help"]
