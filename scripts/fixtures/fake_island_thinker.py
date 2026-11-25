#!/usr/bin/env python3
"""Drop this executable into the fake CLI directory as codex and claude."""
import json
import os
from pathlib import Path
import sys
import time

if sys.argv[1:] == ["features", "list"]:
    print("shell_tool stable true")
    sys.exit()

base = Path(os.environ["HABITAT_THINKER_FAKE_DIR"])
fixture = base / "mode"
mode = fixture.read_text().strip() if fixture.is_file() else "normal"
context = json.loads(sys.stdin.read().split("\n", 1)[1])
group_mode = mode in ("group", "group-moon")
if group_mode:
    mode = "moon" if mode == "group-moon" else "acceptance"
assert not list(Path.cwd().iterdir()), "CLI working directory was not empty"
assert sys.argv[0].endswith(("codex", "claude"))
if sys.argv[0].endswith("claude"):
    assert sys.argv[sys.argv.index("--tools") + 1] == ""
    assert "--no-session-persistence" in sys.argv
else:
    assert "--ephemeral" in sys.argv and "shell_tool" in sys.argv
if mode in ("slow", "timeout"):
    time.sleep(30 if mode == "slow" else 90)
if mode == "crash":
    sys.exit(42)
if mode == "garbled":
    sys.stdout.buffer.write(b"\xffnot JSON")
    sys.exit()
around = context["around"]
events = context["events"]
site = around["suggested_sites"].get("sign")
own_sign = next((p for p in around["pieces"] if p["item"] == "sign"
                 and p.get("owner") == around["resident"]), None)
people = sorted(around["people"], key=lambda p: p["id"] == "human")
play = [p for p in context["play_sites"] if p["kind"] != "play-bench"]
reason = "Leave a sign by the path."
if mode == "illegal":
    steps = [{"action": "shell", "command": "echo refused"}]
elif mode == "gesture":
    steps = [{"action": "gesture", "kind": "wave"}]
elif mode == "moon" and around["position"][0] > -30:
    reason = "Walk over the bridge to Crescent Island."
    steps = [{"action": "go_to", "target": "moon.lookout"}]
elif context["actions"]["held_fish"]:
    reason = "Bring my catch to the fishery."
    pens = context["actions"].get("fisheries", [])
    preferred = "west" if mode == "moon" else "east"
    pen = next((value for value in pens if preferred in value), pens[0] if pens else "")
    if pen:
        steps = [{"action": "stock_fish", "fish_id": context["actions"]["held_fish"], "pen_id": pen}]
    else:
        reason = "Take my catch to the doorstep."
        steps = [{"action": "go_to", "target": "doorstep"},
                 {"action": "put_down", "item": context["actions"]["held_fish"]}]
elif mode in ("acceptance", "moon") and site and (not context["current_plan"] or "bridge" in context["current_plan"]):
    reason = "Try a sign here, change it, and clear the spot."
    steps = [{"action": "place_piece", "item": "sign", "position": site},
             {"action": "name_place", "position": site, "label": "A little view"},
             {"action": "remove_piece", "position": site}]
elif mode in ("acceptance", "moon") and "sign here" in context["current_plan"]:
    reason = "Go say hello."
    steps = [{"action": "go_to", "target": "human"},
             {"action": "say", "target": "human", "text": "Hello there!"}]
elif group_mode and context["current_plan"] and "shuttlecock" not in context["current_plan"] and context.get("group_play"):
    reason = "Invite some neighbors for shuttlecock."
    steps = [{"action": "invite_play", "game": "shuttlecock", "guests": context["group_play"]["guests"][:2]}]
elif mode in ("acceptance", "moon") and "say hello" in context["current_plan"] and context["play_sites"]:
    reason = "Play for a while."
    steps = [{"action": "play_at", "target": (play or context["play_sites"])[0]["id"]}]
elif mode == "acceptance" and "say hello" in context["current_plan"] and context.get("build_sites"):
    reason = "Build a small place to play, then try it."
    projects = context["build_sites"]
    project = next((p for p in projects if p["id"] == "play.swing"), projects[0])
    steps = [{"action": "build", "target": project["id"]},
             {"action": "play_at", "target": project["id"]}]
    if project["wood"] > around["warehouse_wood"]:
        steps.insert(0, {"action": "chop_and_haul", "target": ""})
elif own_sign:
    reason = "Make room for something new."
    steps = [{"action": "remove_piece", "position": own_sign["position"]}]
elif site and (not events or events[-1]["kind"] == "arrived" or "bridge" in context["current_plan"]):
    if site:
        steps = [{"action": "place_piece", "item": "sign", "position": site}]
    else:
        steps = [{"action": "chop_and_haul", "target": ""}]
elif people and "greet" not in context["current_plan"]:
    reason = "Go greet someone nearby."
    target = people[0]["id"]
    steps = [{"action": "go_to", "target": target}, {"action": "say", "target": target, "text": "Hello there!"}]
elif play and "Play for" not in context["current_plan"]:
    reason = "Play for a while."
    steps = [{"action": "play_at", "target": play[0]["id"]}]
else:
    reason = "Try the nearby shore."
    steps = [{"action": "fish"}]
if mode == "slow" and not site:
    steps = [{"action": "gesture", "kind": "wave"}]
print(json.dumps({"reason": reason, "steps": steps}))
