# Codex with SSH and Remote Control

For ChatGPT desktop connections over SSH. Official Python slim base,
native Codex, Python with pip and venv, Node.js with npm/npx, curl,
Dropbear, Git, OpenSSH client, tmux, kubectl and Herdr. Runs as UID/GID `1000:1000`
with Bash as the login shell. Dropbear accepts keys only on port `2222`.

Tool versions and base image tags are defined in the [Dockerfile](Dockerfile).

Connection logs omit TCP connect/disconnect noise before authentication. Successful
logins, authentication failures and server errors remain on stderr. The Bash/sed
wrapper forwards shutdown signals and drains logs before returning the server status.

## Automatic updates

[Renovate](../.github/renovate.json) groups all dependencies declared in this image's
[Dockerfile](Dockerfile) into one update branch, including Codex, Herdr,
kubectl and base images. New branches are created only
on the 1st and 15th of each month in Europe/Lisbon: windows are 14–17 days apart.
Existing branches can be updated and automerged outside those windows once checks pass.
The repository's seven-day release-age delay applies except to kubectl: the K3s
stable datasource does not provide a release timestamp.
A kubectl minor or major upgrade keeps the entire group subject
to manual review under the existing policy.

Codex remains part of the [shared weekly rebuild](../.github/workflows/image.yml).
Source changes, shared workflow changes and manual builds continue to run immediately;
the Renovate schedule does not delay operator fixes. Each build uses the pinned tool
versions from the Dockerfile rather than fetching the latest tool releases at startup.

## Package decisions

- Copy all of `/opt/codex` recursively, preserving metadata and future upstream files.
  A binary allowlist previously omitted `codex-code-mode-host` and broke desktop tools.
- Exclude only `codex-resources/voice`, before copying to the runtime image.
  Its host audio runtime has no required use in this deployment; ordinary SSH does
  not forward laptop audio devices. Restore it only for a concrete use case.
- Symlink `codex`, `codex-code-mode-host` and upstream `rg` into `/usr/local/bin`
  for shell `PATH` access. Do not install a second ripgrep from Debian.
- Keep `codex-resources/bwrap` and `codex-resources/zsh/bin/zsh` in place.
  Codex discovers them through the package layout. The bundled zsh serves internal
  execution; SSH login uses Bash already provided by the base image.
- `codex-code-mode-host` embeds V8; it needs no separate JavaScript installation.
- Copy the Node binary and npm from the official Node slim image; expose npm
  and npx in `PATH` for JavaScript projects and local MCP servers launched by npx.
  The runtime stays on Python slim. Node development headers and Yarn are omitted.
- Python is available as both `python` and `python3`. Create project environments
  with `python -m venv .venv` and install dependencies with `.venv/bin/pip`.
- Herdr is downloaded from its official Linux release for each architecture.
  The image does not bundle any Herdr plugins.
- `KUBECTL_VERSION` tracks the Kubernetes version in K3s's `stable` channel through
  Renovate's `custom.k3sStable` datasource, using the same channel API as the Ansible
  repository. The `v` prefix and `+k3sN` suffix are removed for the upstream kubectl
  download; K3s-only rebuilds do not update the client. SHA-256 verification remains.
  Patch updates follow the repository's CI-gated automerge; minor/major changes
  require review to coordinate with cluster upgrades. The channel does not inspect
  the running cluster, so verify client/server compatibility before deployment.
  The image contains no kubeconfig or Kubernetes credentials; the runtime owns access and RBAC.

The desktop starts `codex app-server` over SSH; no separate service or port is
needed. For terminal use, run `codex --no-daemon`. The managed daemon requires
process-tracking tools omitted from this image.

For a terminal session that keeps running after SSH disconnects:

```bash
tmux new -As codex 'codex --no-daemon'
```

The system config in `/etc/tmux.conf` uses **Ctrl+A** as the prefix.
Press **Ctrl+A twice** to return to the previous window.
Detach with **Ctrl+A, then D** before leaving SSH. Reconnect with
`tmux attach -t codex`. The session also survives an unexpected SSH disconnect;
replacing or restarting the container ends its processes.

Alternatively, run `herdr` over an interactive SSH connection to manage persistent
workspaces. Herdr starts its server on demand; the
image does not start it alongside Dropbear. Its processes survive SSH disconnects,
but end when the container stops, like tmux.

## Runtime setup

The default command is `/usr/local/bin/codex-entrypoint`. It prepares the mounted
home and starts the services selected by two independent environment variables:

| `SSH_ENABLED` | `CODEX_REMOTE_CONTROL_ENABLED` | Services |
| --- | --- | --- |
| `true` (default) | `false` (default) | SSH only |
| `false` | `true` | Remote Control only |
| `true` | `true` | SSH and Remote Control in one container |
| `false` | `false` | Configuration error |

Only the literal values `true` and `false` are accepted; invalid values fail before
initialization. These flags are read at startup, so changing them requires replacing
the container and ends its processes. The entrypoint forwards shutdown to the selected
services. In SSH-only or Remote Control-only mode, the container exits with a nonzero
status if the selected service exits. When both are enabled, SSH failure stops the
container, while Remote Control failure is logged and retried every 30 seconds with
SSH still available. A running container therefore does not prove Remote Control is
connected; check its logs and verify a connection. After a login expires, use SSH to
run `codex logout` and `codex login --device-auth`; a retry uses the renewed login.
Remote Control runs in the foreground with the existing Codex login stored in home;
the image neither creates nor copies operator credentials.

Supply these paths; operator credentials and settings belong in the runtime:

| Path | Requirement |
| --- | --- |
| `/home/codex` | Writable by UID 1000; persist to retain projects, credentials and sessions. |
| `/home/codex/.ssh/authorized_keys` | Read-only public keys, readable by UID 1000, no group/other write permission. |
| `/etc/dropbear` | Writable by UID 1000; persist to retain SSH host keys. |

Keep home and `.ssh` writable only by their owner. Protect credential storage and backups.

The entrypoint creates missing home directories, sets home permissions to `0700`, and
sets `.ssh` to `0700` if it is writable by group or others. Already-safe `.ssh` directories
retain their permissions, including root-owned or read-only mounts with readable keys.
An unsafe directory that cannot be secured stops startup. SSH inputs are required and
prepared only when SSH is enabled.
It reuses an existing host key and generates one only when missing; preserve its storage to retain
the trusted fingerprint. No host key or authorized operator key is baked into the image.

| Environment variable | Default and contract |
| --- | --- |
| `SSH_LISTEN` | `2222`; accepts Dropbear's `[address:]port`. Use `127.0.0.1:2222` for access exclusively through a Pod port-forward. |
| `SSH_HOST_KEY` | `/etc/dropbear/dropbear_ed25519_host_key`; requires writable persistent storage. For a home-only PVC, select `/home/codex/.ssh/dropbear_ed25519_host_key`. |
| `SSH_AUTHORIZED_KEYS_FILE` | `/home/codex/.ssh/authorized_keys`; an existing readable, nonempty public-key file with SSH-compatible ownership and permissions. A different source is copied into home with mode `0600`, supporting a read-only ConfigMap mount. |
| `CODEX_AGENTS_FILE` | Unset; when supplied, must name a readable file and manages the `/home/codex/.codex/AGENTS.md` symlink. Otherwise existing instructions are preserved. |

SSH passes the container environment to authenticated sessions, including an optional
MCP credential. Treat SSH users as having the container's application identity and do not print
the environment or token during validation. The runtime owns the listener exposure and credentials.

The entrypoint unregisters the retired bundled Auto Title and reviewr plugins from
existing homes without deleting their settings. Other plugin registrations and
user settings are preserved.

Herdr's registry and runtime data stay in the writable home. For externally
managed settings, mount `/etc/herdr/config.toml` as a single read-only file and
set `HERDR_CONFIG_PATH=/etc/herdr/config.toml` in the runtime configuration.
This keeps mount-created parent directories outside home, where Herdr needs write access.

The override is optional and is not set by the image. When it is unset, Herdr
continues reading `/home/codex/.config/herdr/config.toml`. No host plugin settings
are copied into the image.

When the container runtime supplies isolation, set `~/.codex/config.toml`:

```toml
sandbox_mode = "danger-full-access"
```

Codex does not disable its sandbox automatically. Bundled Bubblewrap requires
compatible kernel/namespace permissions. The desktop session's permissions must
also allow this mode. `approval_policy` defaults to `on-request`.
See [isolation guidance](https://learn.chatgpt.com/docs/agent-approvals-security).

## Desktop connection

```sshconfig
Host codex-remote
    HostName YOUR_HOST
    Port 2222
    User codex
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

```bash
ssh codex-remote 'codex --version'
ssh -t codex-remote 'codex login --device-auth'
```

Enable [device authentication](https://learn.chatgpt.com/docs/auth#login-on-headless-devices)
for the account/workspace, then add the SSH host under **Settings > Connections**
and select a remote project folder. See [desktop SSH setup](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host).

## Build and test

```bash
cd codex && just
./smoke-test.sh codex
```

Smoke requires Docker, `ssh-keygen` and Python 3 on the test host. It checks SSH
access restrictions, the Bash login shell, Python/pip/venv, curl and Node/npm/npx over
SSH, kubectl client startup over SSH, app-server commands and code-mode execution over SSH, plus home/state/host-key
persistence across replacement, filtered TCP probes, startup errors and shutdown
with an active SSH session. It installs a local npm package and runs its CLI with
npx as UID 1000, without registry access. It also checks that a tmux job survives
an SSH disconnect, reattachment, the Ctrl+A window shortcut and keyboard detach.
Herdr's CLI and retirement of the previously bundled plugins are checked on a
pre-populated home volume, including preservation of a disabled user plugin and
plugin settings, and a read-only mounted `config.toml`. Test resources are cleaned up.

`CODEX_VERSION` in the Dockerfile owns the version. CI publishes amd64/arm64
images with version, commit-SHA and `latest` tags after smoke passes, with build
provenance. Weekly rebuilds refresh Debian packages.
