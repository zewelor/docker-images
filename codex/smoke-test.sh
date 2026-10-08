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
# TCP health checks must not produce unauthenticated connection noise.
docker exec "$container" /bin/bash -c 'for attempt in 1 2 3; do exec 3<>/dev/tcp/127.0.0.1/2222; IFS= read -r -t 2 banner <&3; exec 3<&-; exec 3>&-; done'
# shellcheck disable=SC2016
ssh_command 'set -eu; test -n "${BASH_VERSION:-}"; test "$SHELL" = /bin/bash; bash --version'
# Expand these expressions inside the remote shell.
# shellcheck disable=SC2016
ssh_command 'set -eu; test "$(id -u)" = 1000; codex --version; git --version; python --version; python3 --version; python -m pip --version; curl --version; node --version; npm --version; npx --version'

# A real SSH disconnect must leave the terminal job available for reattachment.
python3 - "$container" <<'PY'
import subprocess
import sys
import time

ssh = ["docker", "exec", "-i", sys.argv[1], "ssh", "-p", "2222", "-i", "/tmp/client-key",
       "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
       "-o", "UserKnownHostsFile=/tmp/known_hosts"]
host = "codex@127.0.0.1"


def remote(command):
    return subprocess.check_output(ssh + [host, command], text=True).strip()


def wait_attached(client):
    for _ in range(30):
        if client.poll() is not None:
            raise RuntimeError(f"SSH exited before attaching: {client.communicate()[0]!r}")
        result = subprocess.run(ssh + [host, "tmux list-clients -F '#{client_session}'"],
                                capture_output=True, text=True)
        if result.returncode == 0 and "ssh-smoke" in result.stdout.splitlines():
            return
        time.sleep(0.1)
    raise RuntimeError("SSH did not attach to tmux within the timeout")


print(remote("tmux -V"))
clients = []
try:
    client = subprocess.Popen(ssh + ["-tt", host,
        "TERM=xterm-256color tmux new-session -s ssh-smoke "
        "'printf \"TMUX_SSH_SMOKE_OK\\n\"; exec sleep 60'"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    clients.append(client)
    wait_attached(client)
    prefix = remote("tmux show-options -gv prefix")
    assert prefix == "C-a", prefix
    pane_pid = remote("tmux display-message -p -t ssh-smoke '#{pane_pid}'")
    assert pane_pid.isdecimal(), pane_pid
    assert "TMUX_SSH_SMOKE_OK" in remote("tmux capture-pane -p -t ssh-smoke")
    # OpenSSH's escape closes the transport while the tmux client is attached.
    output, _ = client.communicate(input=b"\n~.", timeout=5)
    assert client.returncode == 255, (client.returncode, output)
    assert remote("tmux display-message -p -t ssh-smoke '#{pane_pid}'") == pane_pid
    remote(f"kill -0 {pane_pid}")

    remote("tmux new-window -t ssh-smoke -n extra 'sleep 60'")
    client = subprocess.Popen(ssh + ["-tt", host,
        "TERM=xterm-256color tmux attach-session -t ssh-smoke"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    clients.append(client)
    wait_attached(client)
    # Ctrl+A twice returns to the original window; Ctrl+A D detaches.
    client.stdin.write(b"\x01\x01")
    client.stdin.flush()
    for _ in range(30):
        if remote("tmux display-message -p -t ssh-smoke '#{pane_pid}'") == pane_pid:
            break
        time.sleep(0.1)
    else:
        raise RuntimeError("Ctrl+A A did not return to the original tmux window")
    client.stdin.write(b"\x01d")
    client.stdin.flush()
    # Keep SSH stdin open until tmux handles the keys and exits its client.
    client.wait(timeout=5)
    output, _ = client.communicate()
    assert client.returncode == 0, (client.returncode, output)
    assert remote("tmux display-message -p -t ssh-smoke '#{pane_pid}'") == pane_pid
    remote(f"kill -0 {pane_pid}")
    assert "TMUX_SSH_SMOKE_OK" in remote("tmux capture-pane -p -t ssh-smoke")
    print("PASS: tmux job survives SSH disconnect, reattachment, Ctrl+A A and Ctrl+A D")
finally:
    subprocess.run(ssh + [host, "tmux kill-session -t ssh-smoke"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for client in clients:
        if client.poll() is None:
            client.terminate()
            client.wait(timeout=5)
PY

ssh_command 'set -eu; python -m venv /tmp/python-venv; /tmp/python-venv/bin/python -m pip --version'
# Install and run a local CLI without registry access, as the SSH user.
# shellcheck disable=SC2016
ssh_command 'set -eu
    mkdir -p ~/npm-smoke/local-package
    cd ~/npm-smoke
    printf "%s\n" "{\"name\":\"npm-smoke-project\",\"version\":\"1.0.0\",\"private\":true}" > package.json
    printf "%s\n" "{\"name\":\"npm-smoke-cli\",\"version\":\"1.0.0\",\"bin\":{\"npm-smoke\":\"cli.js\"}}" > local-package/package.json
    printf "%s\n" "#!/usr/bin/env node" "require(\"node:assert/strict\").equal(process.getuid(), 1000); console.log(\"NPM_SMOKE_OK\");" > local-package/cli.js
    npm install --offline --ignore-scripts --no-audit --no-fund ./local-package
    test "$(npx --offline --no -- npm-smoke)" = NPM_SMOKE_OK
    echo "PASS: npm local install and npx execution over SSH as UID 1000"'
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

docker logs "$container" > "$test_dir/server.log" 2>&1
if grep -E ' Child connection from | Exit before auth from <[^>]+>: Exited normally$' "$test_dir/server.log"; then
    echo 'ERROR: TCP probe noise reached container logs' >&2
    exit 1
fi
grep -q 'Pubkey auth succeeded' "$test_dir/server.log"
grep -q 'Login attempt with wrong user root' "$test_dir/server.log"

# Keep a session open: its inherited stderr must not block container shutdown.
ssh_command 'echo active; sleep 60' > "$test_dir/active-client.log" 2>&1 &
client_pid=$!
for ((attempt = 0; attempt < 30; attempt++)); do
    if grep -q '^active' "$test_dir/active-client.log"; then break; fi
    sleep 0.1
done
grep -q '^active' "$test_dir/active-client.log"
docker stop -t 3 "$container" >/dev/null
test "$(docker inspect "$container" --format '{{.State.ExitCode}}')" = 0
wait "$client_pid" || true
docker logs "$container" > "$test_dir/stopped-server.log" 2>&1
grep -q 'Terminated by signal' "$test_dir/stopped-server.log"
echo 'PASS: TCP probe noise filtered, auth logs preserved, active SSH shutdown clean'

docker rm "$container" >/dev/null
container=""
start_server
# shellcheck disable=SC2016
ssh_command 'set -eu; test "$(cat ~/project.txt)" = persisted; test "$(cat ~/.codex/smoke-state)" = persisted'
test "$host_key" = "$(docker exec "$container" sha256sum /etc/dropbear/dropbear_ed25519_host_key)"
echo 'PASS: non-root SSH, unauthorized/root login rejection, home/Codex state and host-key persistence'

# A fatal startup error must stay visible and retain a nonzero status.
if docker run --rm --network none --read-only "$image_tag" /usr/local/bin/dropbear-entrypoint -F -E -r /missing-host-key -p 2222 > "$test_dir/startup-error.log" 2>&1; then
    echo 'ERROR: Dropbear accepted missing host keys' >&2
    exit 1
fi
grep -q 'Early exit: No hostkeys available' "$test_dir/startup-error.log"
echo 'PASS: fatal startup diagnostics and exit status preserved'
