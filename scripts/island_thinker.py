"""One stateless text request with allowlisted diagnostics."""
import json
import os
import re
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

FIRST_TIMEOUT = 90
LATER_TIMEOUT = 60
CODEX_DISABLED = (
    "shell_tool", "unified_exec", "shell_snapshot", "apply_patch_freeform",
    "plugins", "remote_plugin", "hooks", "apps", "skill_search",
    "skill_mcp_dependency_install", "multi_agent", "multi_agent_v2", "code_mode",
    "browser_use", "computer_use", "image_generation", "view_image", "sleep_tool",
    "standalone_web_search", "tool_search", "daemon_auto_start", "memories",
    "in_app_local_automation", "goals", "default_mode_request_user_input",
)
CODEX_OVERRIDES = (
    'model_reasoning_effort="low"', 'web_search="disabled"', "mcp_servers={}",
    "plugins={}", "skills.config=[]", "features.skip_host_skill_discovery=true",
    "project_doc_max_bytes=0", "project_doc_fallback_filenames=[]",
    "sandbox_read_only.network_access=false", 'history.persistence="none"',
    "feedback.enabled=false", "analytics.enabled=false", "otel.log_user_prompt=false",
    'otel.exporter="none"', 'otel.trace_exporter="none"', 'otel.metrics_exporter="none"',
    "tools.experimental_request_user_input.enabled=false",
)
CODEX_CORE = ("shell_tool", "unified_exec", "apply_patch_freeform", "plugins",
              "hooks", "apps", "tool_search")

def executable(provider):
    if os.environ.get("HABITAT_THINKER_FAKE_DIR"):
        return shutil.which(os.path.join(os.environ["HABITAT_THINKER_FAKE_DIR"], provider))
    found = shutil.which(provider)
    if found:
        return found
    paths = [os.path.expanduser("~/.local/bin/" + provider),
             "/opt/homebrew/bin/" + provider, "/usr/local/bin/" + provider]
    if provider == "codex":
        paths.append("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
    return next((p for p in paths if shutil.which(p)), None)


def command(binary, provider, work, blocked_mcp=(), supported=CODEX_DISABLED):
    if provider == "codex":
        # Config overrides do not trigger the CLI's unknown --disable rejection.
        features = (("-c", f"features.{name}=false") for name in CODEX_CORE) if supported is None else (
            ("--disable", name) for name in CODEX_DISABLED if name in supported)
        return [binary, "-a", "never", "exec", "--skip-git-repo-check", "--ephemeral",
                "--ignore-rules", "--sandbox", "read-only",
                *[arg for pair in features for arg in pair],
                *[arg for value in CODEX_OVERRIDES for arg in ("-c", value)],
                *[arg for name in blocked_mcp for arg in ("-c", f"mcp_servers.{name}.enabled=false")],
                "-c", "log_dir=" + json.dumps(work), "-c", "sqlite_home=" + json.dumps(work),
                "--color", "never", "--json", "-"]
    return [binary, "--print", "--safe-mode", "--tools", "",
            "--disable-slash-commands", "--strict-mcp-config", "--mcp-config",
            '{"mcpServers":{}}', "--no-session-persistence", "--output-format", "text"]


def protected_command(args, provider, environ, codex_source=None):
    if sys.platform != "darwin":
        return args
    home = Path.home()
    codex_home = codex_source or Path(environ.get("CODEX_HOME") or home / ".codex")
    claude_home = Path(environ.get("CLAUDE_CONFIG_DIR") or home / ".claude")
    protected = {str(p.expanduser().resolve()) for p in
                 (home / ".codex", home / ".claude", home / ".claude.json", codex_home, claude_home)}
    profile = ["(version 1)", "(allow default)"]
    parameters = {}
    for i, path in enumerate(sorted(protected)):
        key = f"PROTECTED_{i}"
        parameters[key] = path
        profile.append(f'(deny file-write* (subpath (param "{key}")))')
    if provider == "codex":
        # Built-in and home skills have no global switch in user config.
        skill_paths = (codex_home / "skills", codex_home / "plugins", home / ".agents/skills",
                       Path("/etc/codex/skills"))
        for i, path in enumerate(skill_paths):
            key = f"SKILLS_{i}"
            parameters[key] = str(path.expanduser().resolve())
            profile.append(f'(deny file-read* (subpath (param "{key}")))')
    return ["/usr/bin/sandbox-exec",
            *[arg for key, value in parameters.items() for arg in ("-D", key + "=" + value)],
            "-p", " ".join(profile), *args]


def codex_runtime(work, environ):
    source = Path(environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser().resolve()
    runtime = Path(work).parent / "codex-home"
    runtime.mkdir(mode=0o700)
    for name in ("config.toml", "auth.json"):
        original = source / name
        if original.is_file():
            (runtime / name).symlink_to(original)
    environ["CODEX_HOME"] = str(runtime)
    return source, runtime


def configured_mcp(binary, work, environ, codex_source):
    # Codex deep merges tables, so an empty override alone preserves existing entries.
    args = protected_command([binary, "mcp", "list", "--json"], "codex", environ, codex_source)
    try:
        result = subprocess.run(args, cwd=work, env=environ, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=6)
        if result.returncode or len(result.stdout) > 262144:
            return None
        rows = json.loads(result.stdout)
        if not isinstance(rows, list) or len(rows) > 128:
            return None
        names = [row.get("name") if isinstance(row, dict) else None for row in rows]
        if not all(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,100}", name) for name in names):
            return None
        return sorted(set(names))
    except (OSError, ValueError, RecursionError, subprocess.TimeoutExpired):
        return None


def supported_features(binary, work, environ, source=None):
    args = [binary, "features", "list"]
    if not environ.get("HABITAT_THINKER_FAKE_DIR"):
        args = protected_command(args, "codex", environ, source)
    try:
        result = subprocess.run(args, cwd=work, env=environ, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3)
        if not result.returncode and len(result.stdout) <= 65536:
            rows = set(re.findall(rb"(?m)^([a-z][a-z0-9_]*)[ \t]+[^\r\n]+[ \t]+(?:true|false)[ \t]*\r?$",
                                  result.stdout))
            if rows:
                supported = {row.decode("ascii") for row in rows}
                for name in CODEX_DISABLED:
                    if name not in supported:
                        print(f"Codex: skipping unsupported feature {name}", file=sys.stderr)
                return supported
    except (OSError, subprocess.TimeoutExpired):
        pass
    print("Codex: feature list unavailable; using core configuration overrides", file=sys.stderr)
    return None


DIAGNOSTICS = {
    "missing": "CLI executable not found",
    "arguments": "CLI rejected its arguments",
    "auth": "CLI requires sign-in",
    "invalid_key": "Provider rejected the API key",
    "network": "Could not reach the provider",
    "model_missing": "Provider does not offer the configured model",
    "config": "Could not safely load the CLI configuration",
    "quota": "Provider quota or rate limit reached",
    "timeout": "CLI exceeded its response deadline",
    "invalid_json": "CLI did not return the expected JSON object",
    "exited": "CLI exited without a usable reply",
}


def error(kind, code=None):
    # Never echo even a substring of stderr: it can contain credentials, paths or prompts.
    return {"error": kind, "exit_code": code, "stderr_summary": DIAGNOSTICS[kind]}


def classify(raw):
    patterns = (
        ("arguments", r"unexpected argument|unknown (?:argument|option|flag)|unrecognized (?:argument|option)|invalid (?:argument|option|value).*--"),
        ("quota", r"rate.limit|usage.limit|quota|insufficient.credit|out of credits|too many requests|\b429\b"),
        ("invalid_key", r"invalid[_ -]?(?:api[_ -]?)?key|incorrect api key|api key (?:is )?(?:invalid|expired|revoked)|bad api key|invalid bearer token"),
        ("model_missing", r"model[_ -]not[_ -]found|unknown model|invalid model|model.{0,120}(?:does not exist|not found|not available|not supported|no access)|(?:does not have|do not have) access to (?:this |the )?model"),
        ("auth", r"not logged in|not authenticated|missing (?:api key|credentials)|unauthori[sz]ed|authentication|login required|run (?:claude |codex )?(?:/login|login)|sign in|\b401\b|\b403\b"),
        ("network", r"connection refused|error sending request|connection reset|failed to connect|network (?:error|unreachable)|dns error|tls error|certificate (?:error|verify)|proxy (?:error|failed)|stream disconnected|connection closed|websocket"),
    )
    return next((kind for kind, pattern in patterns if re.search(pattern, raw, re.I)), "exited")


def read_answer(raw, provider):
    decoded = raw.decode("utf-8")
    if provider != "codex" or os.environ.get("HABITAT_THINKER_FAKE_DIR"):
        return json.loads(decoded), ""
    answer = None
    failures = []
    for line in decoded.splitlines():
        event = json.loads(line)
        if not isinstance(event, dict):
            raise ValueError("Invalid CLI event")
        kind = event.get("type")
        item = event.get("item", {})
        if kind in ("error", "turn.failed"):
            failures.append(str(event.get("message", event.get("error", ""))))
        elif kind == "item.completed" and isinstance(item, dict) and item.get("type") == "agent_message":
            answer = item.get("text")
        elif kind == "turn.completed" and isinstance(answer, str):
            return json.loads(answer), ""
    return None, "\n".join(failures)


def run(provider, base, prompt, mailbox, timeout=FIRST_TIMEOUT):
    deadline = time.monotonic() + timeout
    binary = executable(provider)
    if not binary:
        return error("missing")
    with tempfile.TemporaryDirectory(prefix="thinking-", dir=base) as temporary:
        work = os.path.join(temporary, "work")
        os.mkdir(work, mode=0o700)
        environ = os.environ.copy()
        source = None
        names = ()
        if provider == "codex":
            environ["RUST_LOG"] = "off"
            environ["CODEX_SQLITE_HOME"] = work
        if not environ.get("HABITAT_THINKER_FAKE_DIR"):
            if provider == "codex":
                source, _ = codex_runtime(work, environ)
                names = configured_mcp(binary, work, environ, source)
                if names is None:
                    return error("config")
        if provider == "codex":
            args = command(binary, provider, work, names, supported_features(binary, work, environ, source))
        else:
            args = command(binary, provider, work)
        if not environ.get("HABITAT_THINKER_FAKE_DIR"):
            args = protected_command(args, provider, environ, source)
        with subprocess.Popen(args, cwd=work, env=environ, stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              start_new_session=(os.name != "nt")) as child:
            def stop(_signum=None, _frame=None):
                try:
                    if os.name == "nt":
                        child.kill()
                    else:
                        os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

            signal.signal(signal.SIGTERM, stop)
            timed_out = threading.Event()
            stopped = threading.Event()
            diagnostic = bytearray()
            def drain_stderr():
                while chunk := child.stderr.read(4096):
                    # Drain the pipe while keeping the useful tail bounded.
                    diagnostic.extend(chunk)
                    del diagnostic[:-8192]
            reader = threading.Thread(target=drain_stderr, daemon=True)
            reader.start()
            parent = os.getppid()
            def monitor():
                while not stopped.wait(.15):
                    if not (mailbox / "input").is_file() or os.getppid() != parent:
                        stop()
                        return
            threading.Thread(target=monitor, daemon=True).start()
            def expire():
                timed_out.set()
                stop()
            timer = threading.Timer(max(0, deadline - time.monotonic()), expire)
            timer.start()
            limit = 65536 if provider == "codex" else 16384
            try:
                try:
                    child.stdin.write(prompt)
                    child.stdin.close()
                except BrokenPipeError:
                    pass
                raw = child.stdout.read(limit + 1)
                if len(raw) > limit:
                    stop()
                code = child.wait()
                reader.join()
            finally:
                timer.cancel()
                stopped.set()
            if timed_out.is_set():
                return error("timeout", code)
            if len(raw) > limit:
                return error("invalid_json", code)
            stderr = diagnostic.decode("utf-8", errors="replace")
            try:
                value, events = read_answer(raw, provider)
            except (ValueError, UnicodeError, RecursionError, TypeError):
                value, events = None, ""
            if code or events:
                # Claude can put sign-in and quota errors on stdout in print mode.
                diagnostic_output = raw.decode("utf-8", errors="replace") if provider == "claude" else events
                return error(classify(stderr + "\n" + diagnostic_output), code)
            if not isinstance(value, dict):
                kind = classify(stderr)
                return error("invalid_json" if kind == "exited" else kind, code)
            return {"plan": value, "exit_code": code, "stderr_summary": ""}


def main():
    provider = sys.argv[1]
    mailbox = Path(sys.argv[2])
    if provider == "detect":
        result = {name: bool(executable(name)) for name in ("codex", "claude")}
    elif provider in ("codex", "claude"):
        with (mailbox / "input").open("rb") as stream:
            prompt = stream.read(65537)
        if not 0 < len(prompt) <= 65536:
            result = {"error": "input_too_large"}
        else:
            try:
                timeout = LATER_TIMEOUT if sys.argv[3:] == ["later"] else FIRST_TIMEOUT
                result = run(provider, mailbox.parent, prompt, mailbox, timeout)
            except (FileNotFoundError, PermissionError):
                result = error("missing")
    else:
        result = {"error": "missing"}
    try:
        encoded = json.dumps(result, ensure_ascii=True, allow_nan=False)
    except ValueError:
        encoded = '{"error":"invalid_json"}'
    temporary = mailbox / "reply.tmp"
    temporary.write_text(encoded if len(encoded) <= 32768 else '{"error":"invalid_json"}', encoding="ascii")
    temporary.replace(mailbox / "reply")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RecursionError):
        sys.exit(1)
