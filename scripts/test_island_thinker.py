"""Offline transport and isolation checks for the island CLI helper."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import island_thinker as thinker


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        body = b'{"data":[]}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.requests.append((self.path, payload))
        self.send_error(400, "Offline fixture")


class ThinkerTest(unittest.TestCase):
    def test_feature_list_failure_keeps_core_and_mcp_blocks(self):
        args = thinker.command("codex", "codex", "/tmp/fixture", ("fixture",), None)
        self.assertNotIn("--disable", args)
        self.assertEqual(args[args.index("--sandbox") + 1], "read-only")
        self.assertEqual(args[args.index("-a") + 1], "never")
        self.assertTrue({
            "features.shell_tool=false", "features.unified_exec=false", "features.plugins=false",
            "features.hooks=false", 'web_search="disabled"', "mcp_servers={}",
            "mcp_servers.fixture.enabled=false",
        }.issubset(args))

    @unittest.skipIf(os.name == "nt", "fixture uses a POSIX executable script")
    def test_unknown_feature_does_not_prevent_fake_codex_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = root / "codex"
            cli.write_text(
                f"#!{sys.executable}\n"
                "import sys\n"
                "if sys.argv[1:] == ['features', 'list']:\n"
                "    print('shell_tool stable true')\n"
                "else:\n"
                "    assert 'nonexistent_round_fixture' not in sys.argv\n"
                "    assert sys.argv[sys.argv.index('--disable') + 1] == 'shell_tool'\n"
                "    assert sys.argv[sys.argv.index('--sandbox') + 1] == 'read-only'\n"
                "    assert 'mcp_servers={}' in sys.argv\n"
                "    assert sys.stdin.read() == 'fixture'\n"
                "    print('{\"ok\":true}')\n"
            )
            cli.chmod(0o700)
            (root / "input").touch()
            with patch.dict(os.environ, HABITAT_THINKER_FAKE_DIR=directory), patch.object(
                thinker, "CODEX_DISABLED", ("shell_tool", "nonexistent_round_fixture")
            ):
                self.assertEqual(thinker.run("codex", directory, b"fixture", root)["plan"], {"ok": True})

    def test_invocation_restricts_capabilities_without_overriding_provider(self):
        args = thinker.command("codex", "codex", "/tmp/fixture")
        flags = dict(zip(args, args[1:]))
        self.assertNotIn("--ignore-user-config", args)
        self.assertEqual(flags["--sandbox"], "read-only")
        self.assertEqual(flags["-a"], "never")
        self.assertIn("--ephemeral", args)
        self.assertIn("--ignore-rules", args)
        disabled = {after for before, after in zip(args, args[1:]) if before == "--disable"}
        self.assertTrue({"shell_tool", "unified_exec", "shell_snapshot", "apply_patch_freeform",
                         "plugins", "remote_plugin", "hooks", "apps", "skill_search",
                         "skill_mcp_dependency_install", "multi_agent", "multi_agent_v2",
                         "code_mode", "browser_use", "computer_use", "image_generation",
                         "view_image", "sleep_tool", "standalone_web_search", "tool_search",
                         "daemon_auto_start", "memories", "in_app_local_automation", "goals",
                         "default_mode_request_user_input"} <= disabled)
        overrides = dict(value.split("=", 1) for before, value in zip(args, args[1:]) if before == "-c")
        self.assertEqual({key: overrides[key] for key in (
            "model_reasoning_effort", "web_search", "mcp_servers", "plugins", "skills.config",
            "features.skip_host_skill_discovery", "project_doc_max_bytes",
            "project_doc_fallback_filenames", "sandbox_read_only.network_access",
            "history.persistence", "feedback.enabled", "analytics.enabled", "otel.log_user_prompt",
            "otel.exporter", "otel.trace_exporter", "otel.metrics_exporter",
            "tools.experimental_request_user_input.enabled")}, {
            "model_reasoning_effort": '"low"', "web_search": '"disabled"', "mcp_servers": "{}",
            "plugins": "{}", "skills.config": "[]", "features.skip_host_skill_discovery": "true",
            "project_doc_max_bytes": "0", "project_doc_fallback_filenames": "[]",
            "sandbox_read_only.network_access": "false", "history.persistence": '"none"',
            "feedback.enabled": "false", "analytics.enabled": "false", "otel.log_user_prompt": "false",
            "otel.exporter": '"none"', "otel.trace_exporter": '"none"', "otel.metrics_exporter": '"none"',
            "tools.experimental_request_user_input.enabled": "false",
        })
        self.assertTrue({"model", "model_provider", "model_providers", "cli_auth_credentials_store"}.isdisjoint(overrides))
        claude = thinker.command("claude", "claude", "/tmp/fixture")
        self.assertNotIn("--restricted", claude)
        self.assertTrue({"--safe-mode", "--disable-slash-commands", "--strict-mcp-config",
                         "--no-session-persistence"} <= set(claude))
        self.assertEqual(claude[claude.index("--tools") + 1], "")
        self.assertEqual(json.loads(claude[claude.index("--mcp-config") + 1]), {"mcpServers": {}})
        self.assertEqual((thinker.FIRST_TIMEOUT, thinker.LATER_TIMEOUT), (90, 60))

    def test_error_categories_are_distinct_and_no_raw_diagnostics_escape(self):
        samples = {
            "auth": "Not logged in. Run /login",
            "invalid_key": "401 Incorrect API key provided",
            "network": "Connection refused", "model_missing": "model_not_found",
            "arguments": "unexpected argument --fake", "quota": "429 rate limit",
        }
        for expected, sample in samples.items():
            with self.subTest(category=expected):
                self.assertEqual(thinker.classify(sample), expected)
                self.assertNotIn(sample, thinker.error(expected, 1)["stderr_summary"])

    @unittest.skipUnless(sys.platform == "darwin" and os.environ.get("HABITAT_CODEX_LOCAL_CONTRACT"),
                         "requires installed macOS Codex; uses a loopback HTTP fixture only")
    def test_installed_codex_sends_configured_model_without_tools(self):
        with tempfile.TemporaryDirectory(prefix="kinabode-r12-contract-") as name:
            self.check_installed_codex(Path(name))

    def check_installed_codex(self, root):
        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            source = root / "configured"
            source.mkdir()
            skill = source / "skills" / "fixture-skill"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(
                "---\nname: fixture-skill\ndescription: inherited-skill-marker\n---\n")
            home = root / "user"
            home.mkdir()
            work = root / "work"
            work.mkdir()
            (source / "AGENTS.md").write_text("inherited-doc-marker")
            port = server.server_address[1]
            config = source / "config.toml"
            config.write_text(f'''model = "fixture-model"
model_provider = "fixture"
model_reasoning_effort = "high"
web_search = "live"
[model_providers.fixture]
name = "Fixture"
base_url = "http://127.0.0.1:{port}/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
[mcp_servers.fixture]
command = "/usr/bin/touch"
args = [{json.dumps(str(root / "mcp-started"))}]
[features]
shell_tool = true
plugins = true
hooks = true
view_image = true
''')
            before = config.read_bytes()
            server.requests = []
            threading.Thread(target=server.serve_forever, daemon=True).start()
            try:
                env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "CODEX_HOME": str(source),
                       "CODEX_SQLITE_HOME": str(work), "RUST_LOG": "off"}
                original, _ = thinker.codex_runtime(str(work), env)
                binary = thinker.executable("codex")
                names = thinker.configured_mcp(binary, str(work), env, original)
                self.assertEqual(names, ["fixture"])
                args = thinker.protected_command(thinker.command(binary, "codex", str(work), names), "codex", env, original)
                # The actual CLI sees the fixture config. Deny all traffic except this server.
                profile = args.index("-p") + 1
                args[profile] += f' (deny network-outbound) (allow network-outbound (remote ip "localhost:{port}"))'
                result = subprocess.run(args, input=b"offline fixture", cwd=work, env=env,
                                        capture_output=True, timeout=20)
            finally:
                server.shutdown()
            self.assertTrue(server.requests, result.stderr.decode(errors="replace")
                            + result.stdout.decode(errors="replace"))
            path, request = server.requests[0]
            self.assertEqual(path, "/v1/responses")
            self.assertEqual(request["model"], "fixture-model")
            self.assertEqual(request["reasoning"]["effort"], "low")
            self.assertEqual(request.get("tools", []), [], request.get("tools"))
            self.assertNotIn("inherited-skill-marker", json.dumps(request))
            self.assertNotIn("inherited-doc-marker", json.dumps(request))
            self.assertFalse((root / "mcp-started").exists())
            self.assertEqual(config.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
