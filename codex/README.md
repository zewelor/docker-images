# Codex + SSH

Debian trixie slim with the native Codex binary, Dropbear, Git, OpenSSH client
and ripgrep. No Node.js or npm. Runs as `codex` (`1000:1000`).

The default `CMD` runs key-only SSH on port `2222`. Dropbear generates missing
host keys itself; there is no entrypoint script. Other commands can run directly:

```bash
docker run --rm ghcr.io/zewelor/codex:latest codex --version
```

Runtime storage and SSH keys are supplied by the operator:

- `/home/codex/.ssh/authorized_keys`: public keys; mount this file read-only, readable by UID 1000 and without group/other write permissions.
- `/home/codex`: writable home, including normal Codex state in `~/.codex` and any projects stored here. Persist it to retain credentials and sessions.
- `/etc/dropbear`: writable host-key directory. Persist it to retain the SSH host fingerprint.

Keep the home and `.ssh` directory writable only by their owner. Protect the
home volume and its backups because Codex credentials contain access tokens.

## Command isolation

This image targets environments where the container runtime supplies isolation;
Bubblewrap is omitted. Codex does not automatically disable its own sandbox in
a container. For this deployment model, supply `~/.codex/config.toml`:

```toml
sandbox_mode = "danger-full-access"
```

`approval_policy = "on-request"` is the [default](https://learn.chatgpt.com/docs/config-file/config-sample)
and can be omitted unless you need to override existing configuration or client
settings. There are no [documented environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables)
for these two settings; use `config.toml` or CLI flags.

Alternatively, use `codex --sandbox danger-full-access` for a terminal session.
Isolation then comes from the deployment's filesystem,
process and network restrictions; see [Codex container guidance](https://learn.chatgpt.com/docs/agent-approvals-security).
The desktop client can override sandbox settings per session, so its selected
permissions must also permit operation without Codex's internal sandbox.
The image does not create or override operator configuration.

## ChatGPT desktop app over SSH

The [desktop app](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host)
starts the remote Codex app server through SSH using the user's login shell.
The installed `codex` binary supports this mode; no separate app-server service
or additional exposed port is required.

Add the reachable host to your laptop's `~/.ssh/config`:

```sshconfig
Host codex-remote
    HostName YOUR_HOST
    Port 2222
    User codex
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Confirm `ssh codex-remote 'codex --version'` works. Authenticate remotely with
`ssh -t codex-remote 'codex login --device-auth'`, then open **Settings > Connections**
in the desktop app, add the SSH host and select a remote project folder.
Device authentication must be enabled for your account/workspace; see
[Codex authentication](https://learn.chatgpt.com/docs/auth#login-on-headless-devices).

## Build and verification

```bash
cd codex && just
./smoke-test.sh codex |& tee /tmp/codex-smoke.log
```

The smoke test requires Docker, `ssh-keygen` and Python 3 on the test host. It
checks non-root SSH, unauthorized/root login rejection, an app-server protocol
handshake and command execution over SSH with operator-provided sandbox settings,
and home/Codex-state/host-key persistence across container
replacement. Temporary containers, volumes and client keys are removed on exit.

`CODEX_VERSION` and its Renovate comment in the Dockerfile are the single version
source. Existing repository rules provide branch automerge after CI and the
seven-day release-age delay. Weekly rebuilds refresh unpinned Debian packages.
CI publishes amd64/arm64 images with version, commit-SHA and `latest` tags and
build-provenance attestations after smoke passes.
