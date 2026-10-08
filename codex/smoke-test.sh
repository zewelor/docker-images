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
    container="$(docker run -d --network none --read-only --tmpfs /tmp:mode=1777 --cap-drop ALL \
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
# shellcheck disable=SC2016
ssh_command 'set -eu; test -n "${ZSH_VERSION:-}"; test "$SHELL" = /usr/local/bin/zsh; zsh --version'
# Expand these expressions inside the remote shell.
# shellcheck disable=SC2016
ssh_command 'set -eu; test "$(id -u)" = 1000; codex --version; git --version; python --version; python3 --version; python -m pip --version; curl --version'
ssh_command 'set -eu; python -m venv /tmp/python-venv; /tmp/python-venv/bin/python -m pip --version'
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
            "command": ["/bin/sh", "-c", "set -eu; printf command-ok > command-proof; rg -q '^command-ok$' command-proof; cat command-proof"],
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

# Exercise the helper used by desktop code-mode tools, not only shell execution.
python3 - "$container" <<'PY'
import json
import queue
import struct
import subprocess
import sys
import threading

TIMEOUT = 20
SESSION = "codex-host-smoke"
MARKER = "CODE_MODE_HOST_SMOKE_OK"
command = ["docker", "exec", "-i", sys.argv[1], "ssh", "-p", "2222", "-i", "/tmp/client-key",
           "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
           "-o", "UserKnownHostsFile=/tmp/known_hosts", "codex@127.0.0.1", "codex-code-mode-host"]
proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
frames = queue.Queue()


def read_exact(size):
    data = bytearray()
    while len(data) < size:
        chunk = proc.stdout.read(size - len(data))
        if not chunk:
            if not data and size == 4:
                return None
            raise EOFError("host closed stdout mid-frame")
        data.extend(chunk)
    return bytes(data)

def reader():
    try:
        while True:
            header = read_exact(4)
            if header is None:
                frames.put(None)
                return
            length = struct.unpack("<I", header)[0]
            frames.put(json.loads(read_exact(length)))
    except BaseException as error:
        frames.put(error)

threading.Thread(target=reader, daemon=True).start()

def send(message):
    body = json.dumps(message, separators=(",", ":")).encode()
    proc.stdin.write(struct.pack("<I", len(body)) + body)
    proc.stdin.flush()

def recv():
    message = frames.get(timeout=TIMEOUT)
    if isinstance(message, BaseException):
        raise message
    if message is None:
        raise EOFError("host closed stdout")
    return message

def response(request_id, expected):
    while True:
        message = recv()
        if message.get("type") == "operation/response" and message.get("id") == request_id:
            result = message["result"]
            assert result["status"] == "ok", result
            assert result["value"]["type"] == expected, result
            return result["value"]

try:
    send({"type": "connection/hello", "supportedVersions": [1], "requiredCapabilities": [], "optionalCapabilities": []})
    hello = recv()
    assert hello["type"] == "connection/ready" and hello["selectedVersion"] == 1, hello
    send({"type": "operation/request", "id": 1, "request": {"method": "session/open", "sessionId": SESSION}})
    response(1, "session/ready")
    send({"type": "operation/request", "id": 2, "request": {"method": "session/execute", "sessionId": SESSION, "request": {"tool_call_id": "smoke", "enabled_tools": [], "source": 'text("' + MARKER + '");', "yield_time_ms": 10000, "max_output_tokens": 256}}})
    response(2, "execution/started")
    while True:
        execution = recv()
        if execution.get("type") == "execute/initialResponse" and execution.get("id") == 2:
            break
    result = execution["result"]
    assert result["status"] == "ok" and "Result" in result["value"], result
    assert any(item.get("type") == "input_text" and MARKER in item.get("text", "")
               for item in result["value"]["Result"]["content_items"]), result
    send({"type": "operation/request", "id": 3, "request": {"method": "session/shutdown", "sessionId": SESSION}})
    response(3, "session/closed")
    proc.stdin.close()
    assert proc.wait(timeout=TIMEOUT) == 0, "host exited unsuccessfully"
    print("PASS: V1 handshake, session open, JavaScript output, and session close")
finally:
    if proc.poll() is None:
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
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
