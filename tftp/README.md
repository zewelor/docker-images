Forked from https://github.com/pghalliday-docker/tftp , to add multiarch builds

# tftp

To build

```
docker build --rm --tag=ghcr.io/zewelor/tftp .
```

To run

```
docker run -p 0.0.0.0:69:69/udp -i -t ghcr.io/zewelor/tftp
```

The container runs as a non-root user and listens on the standard TFTP port `69/udp`. It always serves files from `/var/tftpboot`.

**Note:** On older kernels that don't allow unprivileged users to bind to low ports, you may need to run with `--user root` or set `TFTP_PORT` to a higher port (e.g., 1069).

To change the internal listening port, set `TFTP_PORT`:

```
docker run -e TFTP_PORT=1069 -p 0.0.0.0:69:1069/udp -i -t ghcr.io/zewelor/tftp
```

Mounts the following volume for persistent data

```
/var/tftpboot
```

To map the volume to a host directory

```
docker run -p 0.0.0.0:69:69/udp -v /var/tftpboot:/var/tftpboot -i -t ghcr.io/zewelor/tftp
```

Use a read-write bind mount if clients need to upload files. A read-only mount is fine for serving existing files only.
