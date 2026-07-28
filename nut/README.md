# nut

Multiarch Docker image for Network UPS Tools (NUT) daemon.

## Build

To build the image locally:

```bash
just nut/
```

## Run

To run the container, exposing the NUT port `3493`:

```bash
docker run -d \
  --name nut \
  -p 3493:3493 \
  --device=/dev/bus/usb \
  ghcr.io/zewelor/nut
```

> [!NOTE]
> The container runs as the dedicated `nut` user (`100:101`) and does not need `privileged` mode or added Linux capabilities. The mapped USB device must grant that user, or one of its supplemental groups, read/write access. In Kubernetes, use a device plugin for allocation and set an explicit supplemental group matching the device node's group.
