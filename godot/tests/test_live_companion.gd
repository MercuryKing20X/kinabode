extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Link = preload("res://scripts/companion_link.gd")
var world := World.new()
var link: Node
var accepted := false
var saw_observe := false
var got_reply := false
var errors: Array = []

func _initialize() -> void:
	if OS.get_environment("HABITAT_LIVE_TEST") != "1" or not OS.get_environment("HABITAT_DATA_DIR").contains("habitat-live-test-"):
		push_error("Explicit isolated live opt-in required"); quit(1); return
	call_deferred("run")

func run() -> void:
	link = Link.new(); root.add_child(link); link.event_received.connect(receive)
	link.send_message("请先用 habitat_observe 读取 home.tree.01，然后砍这棵树，把全部木材搬进箱子。请简短告诉我你开始了。", world.observe("codex", {"limit": 4}))
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		world.advance(.05)
		await create_timer(.01).timeout
		if not errors.is_empty(): break
		if accepted and got_reply and not world.work.jobs.has("codex") and not link.is_busy():
			var wood := int({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.get("wood", 0))
			print("LIVE_RESULT observe=%s accepted=%s reply=%s chest_wood=%s" % [saw_observe, accepted, got_reply, wood])
			link.shutdown()
			quit(0 if saw_observe and wood == 8 else 1)
			return
	link.shutdown()
	push_error("Live check did not complete: " + str(errors))
	quit(1)

func receive(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"observe":
			saw_observe = true
			link.reply(event.id, world.observe("codex", event.get("query", {})))
		"action":
			var result: Dictionary = world.command("codex", event.command)
			accepted = accepted or (result.ok and event.command.intent == "chop")
			link.reply(event.id, result)
		"assistant": got_reply = true
		"error": errors.append(event.message)
		"question": errors.append("Unexpected question in explicit test instruction")
