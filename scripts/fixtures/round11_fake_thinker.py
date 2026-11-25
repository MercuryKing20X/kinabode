#!/usr/bin/python3
"""Copy as codex or claude into HABITAT_THINKER_FAKE_DIR."""
import json
import os
from pathlib import Path
import sys
import time

if sys.argv[1:] == ["features", "list"]:
    print("shell_tool stable true")
    sys.exit()

base = Path(os.environ["HABITAT_THINKER_FAKE_DIR"])
mode = (base / "mode").read_text().strip()
prompt = sys.stdin.read()
assert not list(Path.cwd().iterdir())
if Path(sys.argv[0]).name == "codex":
    assert "--json" in sys.argv and "shell_tool" in sys.argv
    assert "mcp_servers={}" in sys.argv and 'model_reasoning_effort="low"' in sys.argv
    assert "--ignore-user-config" not in sys.argv
else:
    assert sys.argv[sys.argv.index("--tools") + 1] == ""
    assert "--safe-mode" in sys.argv and "--restricted" not in sys.argv
if mode == "timeout":
    time.sleep(110)
if mode in ("auth", "arguments", "quota", "invalid_key", "network", "model_missing"):
    errors = {"auth": "Not logged in. Run /login", "arguments": "unexpected argument --dummy",
              "quota": "Rate limit reached (429)", "invalid_key": "401 Incorrect API key provided",
              "network": "Failed to connect: connection refused", "model_missing": "model_not_found"}
    print(errors[mode] + " sk-" + "fake-private-test-key /tmp/private-test-path", file=sys.stderr)
    sys.exit(1)
if mode == "invalid":
    print("not json")
elif prompt in ('Reply with {"ok":true}', '回复 {"ok":true}'):
    print('{"ok":true}')
else:
    state = json.loads(prompt.split("\n", 1)[1])
    assert state["events"]
    steps = [{"action": "gesture", "kind": "wave"}]
    print(json.dumps({"reason": "Wave a little hello.",
                      "steps": steps}))
