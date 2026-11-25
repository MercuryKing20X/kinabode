extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failed := false
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var world := World.new()
	# The ambient unit probe owns a fixed scene; daily/wish/personality events are tested separately.
	world.world_id="00000000-0000-4000-8000-000000000192";world.weather.weather_seed=1027
	world.days.config.greeting_after=world.days.day_seconds+1;world.days.config.small_after=world.days.day_seconds+1
	world.personality.config.fact_events_enabled=false
	world.activities.release_follow("codex");world.activities.default_follow_excluded["codex"]=true
	world.director.local_dialogue.next_check=INF
	var life: RefCounted = world.local_companion
	life.rng.seed = 192
	life.set_enabled(true)
	var objects: Dictionary = world.objects.duplicate(true)
	var human: Dictionary = world.actors.human.duplicate(true)
	var shared: Dictionary = world.life.state()
	var all_lines: Array = []
	var seen := 0
	var behaviors: Dictionary = {}
	var valid_routes := true
	for i in range(6000):
		world.advance(.1)
		behaviors[life.kind] = true
		valid_routes = valid_routes and world.walkable("home", world.point(world.actors.codex))
		for event in life.events:
			if event.serial > seen:
				if event.get("delivered",false):all_lines.append(event.duplicate())
				seen = event.serial
	check(valid_routes, "ambient walking stays on validated land")
	check(behaviors.size() >= 4, "local state machine varies its idle behavior")
	check(world.objects == objects and world.life.state() == shared and world.drops.is_empty(), "ten minutes of local life do not consume or invent resources")
	check(world.actors.human == human, "never animates or moves the human")
	check(all_lines.size() >= 8 and all_lines.size() <= 20, "ambient speech is infrequent: "+str(all_lines.size()))
	var spaced := true
	for i in range(1, all_lines.size()):
		spaced = spaced and float(all_lines[i].time) - float(all_lines[i-1].time) >= float(life.config.speech_interval[0])-.1 and all_lines[i].text != all_lines[i-1].text
	check(spaced, "speech cooldown and no immediate repetitions")
	check(all_lines.all(func(event): return event.source == "local_rules"), "all authored dialogue explicitly identifies source")
	life.chatter = false
	var count: int = life.serial
	for i in range(1000): world.advance(.1)
	check(life.serial == count, "muted chatter stays silent")
	life.set_enabled(false)
	var stopped: Array = world.actors.codex.position.duplicate()
	for i in range(1000): world.advance(.1)
	check(world.actors.codex.position == stopped and life.kind.is_empty(), "disable cancels only ambient behavior")
	life.set_enabled(true)
	check(life._start("wander"), "start local wander")
	life.set_held(true)
	stopped = world.actors.codex.position.duplicate()
	for i in range(300): world.advance(.1)
	check(not world._routes.has("codex") and world.actors.codex.position == stopped and not life.greet().ok, "model thinking/question hold cancels wander and blocks local reply")
	life.set_held(false)
	check(life._start("wander"), "restart local wander")
	var wood_before:int=world.storage.count("wood")
	var expected:int=int(world.forest.settings.large_wood if int(world.objects["home.tree.01"].wood_yield)>8 else world.forest.settings.normal_wood)
	check(world.command("codex", {"intent": "chop", "target_id": "home.tree.01"}).ok, "validated task preempts ambient move")
	check(life.kind.is_empty() and not life.owns_route, "local controller relinquishes route ownership")
	for i in range(6000):
		world.advance(.1)
		if not world.work.jobs.has("codex"): break
	check({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.wood == wood_before+expected, "real harvest completes without local interruption")
	world.command("codex", {"intent": "move", "x":Places.point("p_26_8_49_0").x,"y":Places.point("p_26_8_49_0").y})
	for i in range(6000):
		world.advance(.1)
		if not world._routes.has("codex"): break
	check(life._start("rest"), "nearby empty camp seat can be used without food")
	for i in range(150):
		world.advance(.05)
		if world.actors.codex.activity == "local_rest": break
	check(world.actors.codex.activity == "local_rest" and not life.seat_id.is_empty(), "local resident rests on claimed seat")
	check(world.life.station.meals_eaten == 0 and world.life.memories.is_empty(), "rest is never fake eating")
	check(Save.save_world(world, directory), "save during ambient rest")
	var restored := World.new()
	check(Save.load_world(restored, directory).ok and restored.local_companion.kind.is_empty() and restored.work.claims.is_empty() and restored.actors.codex.activity == "idle", "reload stops local routes and releases seat")
	world.command("codex", {"intent": "stop"})
	check(life.seat_id.is_empty() and world.work.claims.is_empty(), "explicit stop releases local seat")
	stopped = world.actors.codex.position.duplicate()
	life.set_held(true); life.set_held(false)
	for i in range(1000): world.advance(.1)
	check(world.actors.codex.position == stopped and life.kind.is_empty(), "explicit stop keeps120sec quiet even after model cancellation hold")
	# UI path: local buttons never start the model process, and settings persist separately.
	var game: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false; game.world.local_companion.rng.seed = 20
	await process_frame
	game.world.command("codex", {"intent": "move", "x":Places.point("p_52_0_44_0").x,"y":Places.point("p_52_0_44_0").y})
	for i in range(6000):
		game.world.advance(.1)
		if not game.world._routes.has("codex"): break
	game._local_interaction(false); game._process(.1)
	check(game.link._pid == -1 and not game.link.is_busy(), "greeting causes zero model startup")
	check(game.view.speech_source == "local_rules" and not game.chat_log.get_parsed_text().contains("日常 ·"), "local greeting retains source without daily prefix in history")
	var prior_turn_key:String=game.link.turn_key
	game.link.turn_key="fixture-real-turn";game.link._busy = true
	game._process(.1)
	check(game.world.local_companion.held and game.view.speech_until == 0, "thinking clears only local bubble and pauses rule decisions")
	game.link._busy = false;game.link.turn_key=prior_turn_key; game.pending_question = "pending-test"
	game._process(.1)
	check(game.world.local_companion.held, "pending question remains protected even without busy flag")
	game.pending_question = ""; game._process(.1)
	game.view.say("真正的模型回复", "model"); game.view.say("本地日常", "local_rules")
	check(game.view.speech == "真正的模型回复", "ambient lines cannot overwrite model speech")
	game.world.local_companion.chatter = false; game._save_local_settings()
	var settings := ConfigFile.new(); settings.load(directory.path_join("local-life.cfg"))
	check(settings.get_value("life", "chatter", true) == false, "chatter preference saved separately from progress")
	game.queue_free(); await process_frame
	print("Local companion: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
