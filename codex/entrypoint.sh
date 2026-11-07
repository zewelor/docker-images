#!/usr/bin/env bash
set -euo pipefail

ssh_enabled="${SSH_ENABLED-true}"
remote_enabled="${CODEX_REMOTE_CONTROL_ENABLED-false}"
case "$ssh_enabled:$remote_enabled" in
    true:true|true:false|false:true) ;;
    false:false) echo 'ERROR: enable SSH_ENABLED or CODEX_REMOTE_CONTROL_ENABLED' >&2; exit 1 ;;
    *) echo 'ERROR: SSH_ENABLED and CODEX_REMOTE_CONTROL_ENABLED must be true or false' >&2; exit 1 ;;
esac

umask 077
mkdir -p "$HOME/.codex"
chmod 700 "$HOME"
if [[ -v CODEX_AGENTS_FILE ]]; then
    if [[ ! -f "$CODEX_AGENTS_FILE" || ! -r "$CODEX_AGENTS_FILE" ]]; then
        echo 'ERROR: CODEX_AGENTS_FILE must name a readable file' >&2
        exit 1
    fi
    agents_file="$CODEX_AGENTS_FILE"
    [[ "$agents_file" == /* ]] || agents_file="$PWD/$agents_file"
    ln -sfnT "$agents_file" "$HOME/.codex/AGENTS.md"
fi

if [[ "$ssh_enabled" == true ]]; then
    mkdir -p "$HOME/.ssh"
    # Safe directories may be root-owned or mounted read-only.
    ssh_mode="$(stat -Lc '%a' "$HOME/.ssh")"
    if (( (8#$ssh_mode & 0022) != 0 )); then
        chmod 700 "$HOME/.ssh"
    fi
    authorized_keys="${SSH_AUTHORIZED_KEYS_FILE-$HOME/.ssh/authorized_keys}"
    if [[ ! -s "$authorized_keys" || ! -r "$authorized_keys" ]]; then
        echo 'ERROR: SSH_AUTHORIZED_KEYS_FILE must name a readable, nonempty file' >&2
        exit 1
    fi
    if [[ ! "$authorized_keys" -ef "$HOME/.ssh/authorized_keys" ]]; then
        cat "$authorized_keys" > "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
    fi
    host_key="${SSH_HOST_KEY-/etc/dropbear/dropbear_ed25519_host_key}"
    [[ "$host_key" == /* ]] || host_key="$PWD/$host_key"
    mkdir -p "$(dirname "$host_key")"
    if [[ ! -f "$host_key" ]]; then
        dropbearkey -t ed25519 -f "$host_key" >/dev/null
    fi
    chmod 600 "$host_key"
fi

herdr plugin link /opt/herdr/plugins/auto-title
# Remove the retired bundled plugin from persistent homes, preserving its settings.
reviewr_installed="$(herdr plugin list --json | python3 -c '
import json, sys
plugins = json.load(sys.stdin)["result"]["plugins"]
print(any(plugin["plugin_id"] == "persiyanov.reviewr" for plugin in plugins))
')"
if [[ "$reviewr_installed" == True ]]; then
    herdr plugin uninstall persiyanov.reviewr
fi
cd "$HOME"

remote_pid=
ssh_pid=
# Invoked by the EXIT trap.
# shellcheck disable=SC2329
stop() {
    trap '' TERM INT
    [[ -z "$remote_pid" ]] || kill -INT "$remote_pid" 2>/dev/null || true
    [[ -z "$ssh_pid" ]] || kill -TERM "$ssh_pid" 2>/dev/null || true
    wait || true
}
trap 'stop' EXIT
trap 'exit 0' TERM INT
pids=()
if [[ "$ssh_enabled" == true ]]; then
    /usr/local/bin/dropbear-entrypoint -F -E -e -s -w -r "$host_key" -p "${SSH_LISTEN-2222}" &
    ssh_pid=$!
    pids+=("$ssh_pid")
fi
if [[ "$remote_enabled" == true ]]; then
    codex remote-control --no-daemon &
    remote_pid=$!
    pids+=("$remote_pid")
fi
wait -n "${pids[@]}"
# A selected service exiting, even successfully, requires a container restart.
exit 1
