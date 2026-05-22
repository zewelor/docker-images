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
> The container defaults to `USER 0` (root) and expects mapped USB device access so `libusb` and the NUT driver (`upsdrvctl`) can interface with your physical UPS system without requiring container-wide `privileged` permissions.
