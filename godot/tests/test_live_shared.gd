extends SceneTree
const World = preload("res://scripts/world_state.gd")
const Link = preload("res://scripts/companion_link.gd")
var world := World.new()
var link: Node
var observed := false
var accepted := false
var replied := false
var errors: Array = []
func _initialize() -> void:
	if OS.get_environment("HABITAT_LIVE_TEST") != "1" or not OS.get_environment("HABITAT_DATA_DIR").contains("habitat-live-test-"): quit(1); return
	call_deferred("run")
func run() -> void:
	# Preparation uses actual game jobs, never injected inventory.
	for command in [{"intent": "chop", "target_id": "home.tree.01"}, {"intent": "forage", "target_id": "home.mushrooms.1"}]:
		if not world.command("human", command).ok: quit(1); return
		for i in range(6000):
			world.advance(.1)
			if not world.work.jobs.has("human"): break
	link = Link.new(); root.add_child(link); link.event_received.connect(receive)
	link.send_message("请先主动观察一下，然后从箱子拿木材和蘑菇，去 home.barbecue 准备烧烤并生火。只负责准备生火，这轮不要翻面或吃。请简短回应。", world.observe("codex", {"limit": 3}))
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		await create_timer(.01).timeout
		world.advance(.05)
		if not errors.is_empty(): break
		if observed and accepted and replied and not link.is_busy() and not world.work.jobs.has("codex"):
			print("LIVE_SHARED observed=%s accepted=%s replied=%s fuel_used=%s state=%s" % [observed, accepted, replied, world.life.station.fuel_used, world.life.station.state])
			link.shutdown(); quit(0 if world.life.station.fuel_used == 2 else 1); return
	link.shutdown(); push_error("Live shared test failed: " + str(errors)); quit(1)
func receive(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"observe": observed = true; link.reply(event.id, world.observe("codex", event.get("query", {})))
		"action":
			var result: Dictionary = world.command("codex", event.command)
			accepted = accepted or (result.ok and event.command.intent == "barbecue")
			link.reply(event.id, result)
		"assistant": replied = true
		"error": errors.append(event.message)
		"question": errors.append("Unexpected question")
