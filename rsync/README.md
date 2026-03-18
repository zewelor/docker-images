# rsync

Multiarch Docker image for rsync based on Alpine.

## Usage

### As a client

```bash
docker run --rm ghcr.io/zewelor/rsync --version
```

### As a daemon (rsyncd)

The image includes the `root` user in `/etc/passwd`, so you can use either `uid = root` or `uid = 0` in your configuration.

Example docker-compose:
```yaml
rsync-server:
  image: ghcr.io/zewelor/rsync
  volumes:
    - ./rsyncd.conf:/etc/rsyncd.conf:ro
    - /path/to/backups:/backups
  command: --daemon --config=/etc/rsyncd.conf --port=873 --no-detach
  ports:
    - 873:873
```

Example rsyncd.conf:
```
pid file = /run/rsyncd.pid
log file = /dev/stdout

[backups]
uid = root
gid = root
use chroot = no
path = /backups
read only = false
write only = true
```

## Why root?

This image runs as root (UID 0) to properly handle file ownership preservation during backups.
