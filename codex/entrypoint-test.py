#!/usr/bin/env python3
"""Behavioral checks for the single-container SSH and Remote Control entrypoint."""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ENTRYPOINT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("entrypoint.sh")

STUB = r'''#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path

name = Path(sys.argv[0]).name
state = Path(os.environ["STATE_DIR"])
service = "ssh" if name == "ssh-wrapper" else name

def record(path, value=""):
    (state / path).write_text(value)

if name == "herdr":
    registry = state / "plugins.json"
    plugins = json.loads(registry.read_text()) if registry.exists() else []
    if sys.argv[1:3] == ["plugin", "list"]:
        print(json.dumps({"result": {"plugins": plugins}}))
    elif sys.argv[1:3] == ["plugin", "uninstall"]:
        plugins = [p for p in plugins if p["plugin_id"] != sys.argv[3]]
        registry.write_text(json.dumps(plugins))
    sys.exit(0)
if name == "dropbearkey":
    if os.environ.get("FAIL_KEYGEN") == "true":
        sys.exit(44)
    target = Path(sys.argv[sys.argv.index("-f") + 1])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("synthetic-host-key-" + os.urandom(16).hex() + "\n")
    sys.exit(0)

with (state / (service + ".args")).open("w") as stream:
    stream.write("\0".join(sys.argv[1:]))

def stop(signum, _frame):
    record(service + ".stopped", str(signum))
    sys.exit(0)

signal.signal(signal.SIGINT if service == "codex" else signal.SIGTERM, stop)
record(service + ".ready", str(os.getpid()))
while True:
    exit_file = state / (service + ".exit")
    if exit_file.exists():
        sys.exit(int(exit_file.read_text()))
    time.sleep(0.01)
'''


def make_harness(root):
    root.mkdir(parents=True, exist_ok=True)
    state = root / "state"
    state.mkdir()
    home = root / "home"
    home.mkdir(mode=0o777)
    config = root / "config"
    config.mkdir()
    bindir = root / "bin"
    bindir.mkdir()
    for name in ("herdr", "codex", "ssh-wrapper", "dropbearkey"):
        tool = bindir / name
        tool.write_text(STUB)
        tool.chmod(0o755)
    script = ENTRYPOINT.read_text()
    script = script.replace("/usr/local/bin/dropbear-entrypoint", str(bindir / "ssh-wrapper"))
    script = script.replace("/usr/sbin/dropbear", str(bindir / "ssh-wrapper"))
    script = script.replace("/home/codex", str(home)).replace("/etc/codex", str(config))
    runnable = root / "entrypoint-under-test.sh"
    runnable.write_text(script)
    return state, home, config, bindir, runnable


def environment(state, home, bindir, extra=None):
    result = {"PATH": f"{bindir}:/usr/bin:/bin", "HOME": str(home), "STATE_DIR": str(state)}
    result.update(extra or {})
    return result


def start(script, env):
    return subprocess.Popen(["bash", str(script)], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, start_new_session=True)


def wait_for(process, required=(), forbidden=(), timeout=4):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = [path for path in forbidden if path.exists()]
        assert not found, f"unexpected child started: {found[0].name}"
        if all(path.exists() for path in required):
            return
        if process.poll() is not None:
            out, err = process.communicate()
            raise AssertionError(f"entrypoint exited early ({process.returncode}): {out} {err}")
        time.sleep(0.01)
    raise AssertionError(f"startup timed out waiting for {[p.name for p in required]}")


def finish(process, signal_number=None):
    if signal_number is not None:
        process.send_signal(signal_number)
    try:
        return process.communicate(timeout=5)
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def check_preflight(script, state, home, bindir, extra):
    process = start(script, environment(state, home, bindir, extra))
    try:
        out, err = process.communicate(timeout=5)
        assert process.returncode != 0, (out, err)
        assert not list(state.glob("*.ready")), "preflight failure started a service"
    finally:
        finish(process, signal.SIGTERM)


def check_remote_only(root):
    state, home, _config, bindir, script = make_harness(root)
    agents = root / "agents.md"
    agents.write_text("synthetic agent instructions\n")
    # Missing SSH inputs must be irrelevant; a relative managed instruction path must work.
    env = environment(state, home, bindir, {
        "SSH_ENABLED": "false", "CODEX_REMOTE_CONTROL_ENABLED": "true",
        "SSH_AUTHORIZED_KEYS_FILE": str(root / "missing-authorized-keys"),
        "SSH_HOST_KEY": str(root / "missing-host-key"), "FAIL_KEYGEN": "true",
        "CODEX_AGENTS_FILE": os.path.relpath(agents),
    })
    process = start(script, env)
    try:
        wait_for(process, required=[state / "codex.ready"], forbidden=[state / "ssh.ready"])
        assert (state / "codex.args").read_text().split("\0") == ["remote-control", "--no-daemon"]
        assert (home / ".codex/AGENTS.md").read_text() == agents.read_text()
        agents.write_text("updated managed instructions\n")
        assert (home / ".codex/AGENTS.md").read_text() == agents.read_text()
    finally:
        out, err = finish(process, signal.SIGTERM)
    assert process.returncode == 0, (out, err)
    assert (state / "codex.stopped").read_text() == str(signal.SIGINT)
    assert not (state / "ssh.ready").exists()


def check_removed_plugin(root):
    state, home, _config, bindir, script = make_harness(root)
    registry = state / "plugins.json"
    registry.write_text('[{"plugin_id": "persiyanov.reviewr"}, {"plugin_id": "smoke.user"}]')
    process = start(script, environment(state, home, bindir, {
        "SSH_ENABLED": "false", "CODEX_REMOTE_CONTROL_ENABLED": "true",
    }))
    try:
        wait_for(process, required=[state / "codex.ready"])
        assert json.loads(registry.read_text()) == [{"plugin_id": "smoke.user"}], registry.read_text()
    finally:
        finish(process, signal.SIGTERM)


def check_ssh_setup(root, combined=False):
    state, home, _config, bindir, script = make_harness(root)
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir(mode=0o777)
    ssh_dir.chmod(0o777)
    home.chmod(0o777)
    source = root / "mounted-authorized-keys"
    source.write_text("ssh-ed25519 synthetic-key test\n")
    source.chmod(0o644)
    key = root / "host-key"
    extra = {"SSH_HOST_KEY": str(key), "STATE_DIR": str(state)}
    if combined:
        extra.update({"SSH_ENABLED": "true", "CODEX_REMOTE_CONTROL_ENABLED": "true",
                      "SSH_AUTHORIZED_KEYS_FILE": str(source), "SSH_LISTEN": "127.0.0.1:2222"})
    else:
        extra["SSH_AUTHORIZED_KEYS_FILE"] = str(source)
    process = start(script, environment(state, home, bindir, extra))
    try:
        expected = [state / "ssh.ready"] + ([state / "codex.ready"] if combined else [])
        wait_for(process, required=expected)
        assert (home / ".codex").is_dir()
        assert home.stat().st_mode & 0o777 == 0o700
        assert ssh_dir.stat().st_mode & 0o777 == 0o700
        assert (home / ".ssh/authorized_keys").read_text() == source.read_text()
        assert (home / ".ssh/authorized_keys").stat().st_mode & 0o777 == 0o600
        original_host_key = key.read_text()
        assert original_host_key
        assert key.stat().st_mode & 0o777 == 0o600
        args = (state / "ssh.args").read_text().split("\0")
        listen = "127.0.0.1:2222" if combined else "2222"
        assert args[args.index("-r") + 1] == str(key)
        assert args[args.index("-p") + 1] == listen
        if combined:
            assert (state / "codex.args").read_text().split("\0") == ["remote-control", "--no-daemon"]
    finally:
        finish(process, signal.SIGTERM)

    if combined:
        return
    assert not (state / "codex.ready").exists(), "default startup enabled Remote Control"
    # Reuse is checked once, in SSH-only mode; the key identity must remain unchanged.
    second = root / "second"
    second.mkdir()
    state2 = second / "state"
    state2.mkdir()
    env2 = environment(state2, home, bindir, {"SSH_HOST_KEY": str(key),
                           "SSH_AUTHORIZED_KEYS_FILE": str(source)})
    process = start(script, env2)
    try:
        wait_for(process, required=[state2 / "ssh.ready"])
        assert key.read_text() == original_host_key, "host key changed after restart"
    finally:
        finish(process, signal.SIGTERM)


def check_default_authorized_keys(root, directory_mode):
    state, home, _config, bindir, script = make_harness(root)
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir()
    keys = ssh_dir / "authorized_keys"
    keys.write_text("ssh-ed25519 read-only-source test\n")
    keys.chmod(0o444)
    ssh_dir.chmod(directory_mode)
    key = root / "host-key"
    process = start(script, environment(state, home, bindir, {"SSH_HOST_KEY": str(key)}))
    try:
        wait_for(process, required=[state / "ssh.ready"])
        assert keys.read_text() == "ssh-ed25519 read-only-source test\n"
        assert keys.stat().st_mode & 0o777 == 0o444, "default authorized_keys must be usable without chmod"
        assert home.stat().st_mode & 0o777 == 0o700
        assert ssh_dir.stat().st_mode & 0o777 == directory_mode, "safe SSH directory permissions changed"
    finally:
        finish(process, signal.SIGTERM)


def check_remaining_failures(root):
    for extra in ({"SSH_ENABLED": "false", "CODEX_REMOTE_CONTROL_ENABLED": "false"},
                  {"SSH_ENABLED": "TRUE"}, {"CODEX_REMOTE_CONTROL_ENABLED": "1"}):
        case = root / str(len(list(root.iterdir())))
        case.mkdir()
        state, home, _config, bindir, script = make_harness(case)
        check_preflight(script, state, home, bindir, extra)

    for fail_keygen, source_state in ((True, "valid"), (False, "missing"), (False, "empty")):
        case = root / f"ssh-failure-{fail_keygen}-{source_state}"
        case.mkdir()
        state, home, _config, bindir, script = make_harness(case)
        source = case / "authorized-keys"
        if source_state == "valid":
            source.write_text("ssh-ed25519 synthetic-key test\n")
        elif source_state == "empty":
            source.touch()
        extra = {"SSH_AUTHORIZED_KEYS_FILE": str(source), "SSH_HOST_KEY": str(case / "host-key")}
        if fail_keygen:
            extra["FAIL_KEYGEN"] = "true"
        check_preflight(script, state, home, bindir, extra)


def check_shutdown_and_sibling_exit(root):
    cases = [(signal.SIGTERM, None, None), (signal.SIGINT, None, None)]
    cases += [(None, service, code) for service in ("codex", "ssh") for code in (0, 19)]
    for index, (external_signal, exiting, exit_code) in enumerate(cases):
        case = root / str(index)
        state, home, _config, bindir, script = make_harness(case)
        ssh_dir = home / ".ssh"
        ssh_dir.mkdir()
        (ssh_dir / "authorized_keys").write_text("ssh-ed25519 synthetic-key test\n")
        env = environment(state, home, bindir, {
            "SSH_ENABLED": "true", "CODEX_REMOTE_CONTROL_ENABLED": "true",
            "SSH_HOST_KEY": str(case / "host-key"),
        })
        process = start(script, env)
        try:
            wait_for(process, required=[state / "ssh.ready", state / "codex.ready"])
            if exiting:
                (state / f"{exiting}.exit").write_text(str(exit_code))
            out, err = finish(process, external_signal)
            if external_signal:
                assert process.returncode == 0, (out, err)
                stopped = ("codex", "ssh")
            else:
                assert process.returncode != 0, (exiting, exit_code, out, err)
                stopped = ("ssh" if exiting == "codex" else "codex",)
            for service in stopped:
                expected = signal.SIGINT if service == "codex" else signal.SIGTERM
                assert (state / f"{service}.stopped").read_text() == str(expected)
        finally:
            finish(process)


def main():
    with tempfile.TemporaryDirectory(prefix="codex-entrypoint-test-") as temporary:
        root = Path(temporary)
        check_remote_only(root / "remote-only")
        check_removed_plugin(root / "removed-plugin")
        (root / "ssh-only").mkdir()
        check_ssh_setup(root / "ssh-only")
        (root / "combined").mkdir()
        check_ssh_setup(root / "combined", combined=True)
        for mode in (0o700, 0o755, 0o555):
            check_default_authorized_keys(root / f"default-keys-{mode:o}", mode)
        (root / "failures").mkdir()
        check_remaining_failures(root / "failures")
        (root / "shutdown").mkdir()
        check_shutdown_and_sibling_exit(root / "shutdown")
    print("PASS: entrypoint flags, SSH key handling, Remote Control, shutdown and failures")


if __name__ == "__main__":
    main()
