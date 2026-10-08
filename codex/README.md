# Codex + SSH

For ChatGPT desktop connections over SSH. Official `python:3-slim-trixie` base,
native Codex, Python 3 with pip and venv, Node.js 24 with npm/npx, curl,
Dropbear, Git, OpenSSH client and tmux. Runs as UID/GID `1000:1000`
with Bash as the login shell. Dropbear accepts keys only on port `2222`.

Connection logs omit TCP connect/disconnect noise before authentication. Successful
logins, authentication failures and server errors remain on stderr. The Bash/sed
wrapper forwards shutdown signals and drains logs before returning the server status.

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
- Copy the Node binary and npm from official `node:24-trixie-slim`; expose npm
  and npx in `PATH` for JavaScript projects and local MCP servers launched by npx.
  The runtime stays on Python slim. Node development headers and Yarn are omitted.
- Python is available as both `python` and `python3`. Create project environments
  with `python -m venv .venv` and install dependencies with `.venv/bin/pip`.

The desktop starts `codex app-server` over SSH; no separate service or port is
needed. For terminal use, run `codex --no-daemon`. The managed daemon requires
process-tracking tools omitted from this image.

For a terminal session that keeps running after SSH disconnects:

```bash
tmux new -As codex
codex --no-daemon
```

Detach with **Ctrl+B, then D** before leaving SSH. Reconnect with
`tmux attach -t codex`. The session also survives an unexpected SSH disconnect;
replacing or restarting the container ends its processes.

## Runtime setup

Supply these paths; the image creates no operator configuration:

| Path | Requirement |
| --- | --- |
| `/home/codex` | Writable by UID 1000; persist to retain projects, credentials and sessions. |
| `/home/codex/.ssh/authorized_keys` | Read-only public keys, readable by UID 1000, no group/other write permission. |
| `/etc/dropbear` | Writable by UID 1000; persist to retain SSH host keys. |

Keep home and `.ssh` writable only by their owner. Protect credential storage and backups.

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
SSH, app-server commands and code-mode execution over SSH, plus home/state/host-key
persistence across replacement, filtered TCP probes, startup errors and shutdown
with an active SSH session. It installs a local npm package and runs its CLI with
npx as UID 1000, without registry access. It also checks that a tmux job survives
an SSH disconnect, reattachment and keyboard detach. Test resources are cleaned up.

`CODEX_VERSION` in the Dockerfile owns the version. CI publishes amd64/arm64
images with version, commit-SHA and `latest` tags after smoke passes, with build
provenance. Weekly rebuilds refresh Debian packages.
