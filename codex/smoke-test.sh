#!/usr/bin/env bash
set -euo pipefail

image_tag="${1:?Usage: $0 <image-tag>}"
test_dir="$(mktemp -d)"
container=""
home_volume=""
host_keys_volume=""

cleanup() {
    status=$?
    if [[ -n "$container" ]]; then
        if (( status != 0 )); then docker logs "$container" >&2 || true; fi
        docker rm -f "$container" >/dev/null || true
    fi
    for volume in "$home_volume" "$host_keys_volume"; do
        if [[ -n "$volume" ]]; then docker volume rm "$volume" >/dev/null || true; fi
    done
    rm -rf "$test_dir"
}
trap cleanup EXIT

docker run --rm --network none "$image_tag" codex --version

ssh-keygen -q -t ed25519 -N '' -f "$test_dir/client"
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/untrusted"
chmod 644 "$test_dir/client.pub"
home_volume="$(docker volume create)"
host_keys_volume="$(docker volume create)"

start_server() {
    container="$(docker run -d --network none --cap-drop ALL \
        --security-opt no-new-privileges \
        --mount "type=volume,src=$home_volume,dst=/home/codex" \
        --mount "type=volume,src=$host_keys_volume,dst=/etc/dropbear" \
        --mount "type=bind,src=$test_dir/client.pub,dst=/home/codex/.ssh/authorized_keys,readonly" \
        "$image_tag")"
    docker exec -i "$container" sh -c 'umask 077; cat > /tmp/client-key' < "$test_dir/client"
    for ((attempt = 0; attempt < 30; attempt++)); do
        if ssh_command true >/dev/null 2>&1; then return; fi
        sleep 1
    done
    echo 'ERROR: SSH did not become ready' >&2
    return 1
}

ssh_command() {
    docker exec "$container" ssh -p 2222 -i /tmp/client-key \
        -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=2 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/known_hosts \
        codex@127.0.0.1 "$@"
}

start_server
# Expand these expressions inside the remote shell.
# shellcheck disable=SC2016
ssh_command 'set -eu; test "$(id -u)" = 1000; codex --version; git --version'
ssh_command 'set -eu; printf persisted > ~/project.txt; printf persisted > ~/.codex/smoke-state'
# The test container supplies isolation; operator configuration selects that mode.
ssh_command "printf '%s\n' 'sandbox_mode = \"danger-full-access\"' 'approval_policy = \"on-request\"' > ~/.codex/config.toml"
host_key="$(docker exec "$container" sha256sum /etc/dropbear/dropbear_ed25519_host_key)"

python3 - "$container" <<'PY'
import json
import queue
import subprocess
import sys
import threading
import time

command = ["docker", "exec", "-i", sys.argv[1], "ssh", "-p", "2222", "-i", "/tmp/client-key",
           "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
           "-o", "UserKnownHostsFile=/tmp/known_hosts", "codex@127.0.0.1",
           "codex app-server --listen stdio://"]
with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as client:
    responses = queue.Queue()

    def read_output():
        for line in client.stdout:
            responses.put(line)
        responses.put("")

    threading.Thread(target=read_output, daemon=True).start()

    def request(request_id, method, params):
        client.stdin.write(json.dumps({"id": request_id, "method": method, "params": params}) + "\n")
        client.stdin.flush()
        deadline = time.monotonic() + 15
        while True:
            try:
                line = responses.get(timeout=max(0, deadline - time.monotonic()))
            except queue.Empty:
                raise RuntimeError(f"No {method} response within 15 seconds")
            if not line:
                raise RuntimeError(f"App-server closed before replying to {method}")
            response = json.loads(line)
            if response.get("id") == request_id:
                assert "error" not in response, response
                return response

    try:
        response = request(1, "initialize", {
            "clientInfo": {"name": "codex_image_smoke", "version": "1.0.0"}})
        assert response["result"]["codexHome"] == "/home/codex/.codex", response
        client.stdin.write('{"method":"initialized","params":{}}\n')
        client.stdin.flush()
        print("PASS: app-server initialize over SSH:", json.dumps(response))
        response = request(2, "command/exec", {
            "command": ["/bin/sh", "-c", "printf command-ok > command-proof; cat command-proof"],
            "cwd": "/home/codex", "timeoutMs": 10000})
        assert response["result"]["exitCode"] == 0, response
        assert response["result"]["stdout"] == "command-ok", response
        print("PASS: app-server command execution using operator sandbox configuration")
    finally:
        client.stdin.close()
        client.terminate()
        try:
            client.wait(timeout=5)
        except subprocess.TimeoutExpired:
            client.kill()
            client.wait()
            raise
PY

docker exec -i "$container" sh -c 'umask 077; cat > /tmp/untrusted-key' < "$test_dir/untrusted"
if docker exec "$container" ssh -p 2222 -i /tmp/untrusted-key \
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=/tmp/known_hosts codex@127.0.0.1 true; then
    echo 'ERROR: SSH accepted an unauthorized key' >&2
    exit 1
fi
if docker exec "$container" ssh -p 2222 -i /tmp/client-key \
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=/tmp/known_hosts root@127.0.0.1 true; then
    echo 'ERROR: SSH accepted root login' >&2
    exit 1
fi

docker rm -f "$container" >/dev/null
container=""
start_server
# shellcheck disable=SC2016
ssh_command 'set -eu; test "$(cat ~/project.txt)" = persisted; test "$(cat ~/.codex/smoke-state)" = persisted'
test "$host_key" = "$(docker exec "$container" sha256sum /etc/dropbear/dropbear_ed25519_host_key)"
echo 'PASS: non-root SSH, unauthorized/root login rejection, home/Codex state and host-key persistence'
