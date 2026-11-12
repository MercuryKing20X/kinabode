extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Save = preload("res://scripts/save_store.gd")
const Motion = preload("res://scripts/actor_motion.gd")
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func fixture() -> RefCounted:
	var world := World.new()
	world.residents.provision(world)
	world.activities.release_follow("codex");world.activities.default_follow_excluded["codex"]=true
	world.advance(80)
	world.local_companion.rng.seed = 42
	world.local_companion.set_enabled(true)
	return world
func resources(world: RefCounted) -> Dictionary:
	var carry := {}
	for id in world.actors: carry[id] = world.actors[id].carry.duplicate(true)
	var farming: Dictionary = world.farms.saved().duplicate(true); farming.erase("clock")
	return {"objects":world.objects.duplicate(true),"carry":carry,"drops":world.drops.duplicate(true),"farms":farming,"leisure":world.leisure.saved().duplicate(true)}
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var world := World.new()
	check(not world.flower_gifts.eligible("codex"), "flowers never trigger immediately on opening")
	check(not world.flower_gifts.patches.is_empty() and world.flower_gifts.patches.all(func(p):return world.walkable("home",p.point) and not world.Layout.near_road(world.catalog.regions.home.layout,p.point,.45)), "decorative flower anchors lie beside roads on walkable land")
	world = fixture()
	var initial := resources(world)
	var human: Dictionary = world.actors.human.duplicate(true)
	check(world.local_companion._start("flower_gift"), "idle resident can begin real walk to roadside flowers")
	world.director.routines["companion-2"].set_enabled(true)
	check(not world.director.routines["companion-2"]._start("flower_gift"), "only one resident offers flowers at a time")
	world.director.routines["companion-2"].set_enabled(false)
	var phases := {}
	var shown := false
	for tick in range(800):
		if not world.flower_gifts.active.is_empty():
			phases[world.flower_gifts.active.phase] = true
			shown = shown or bool(world.flower_gifts.active.delivered)
		world.advance(.05)
		if world.local_companion.kind.is_empty(): break
	check(phases.has("approach") and phases.has("picking") and phases.has("bringing") and phases.has("offering") and shown, "gesture completes approach, bend, carry and actual nearby offer")
	check(world.actors.human == human, "gift never takes control of human")
	check(resources(world) == initial and world.work.jobs.is_empty() and world.drops.is_empty(), "cosmetic gift changes no crop, material, carry, drops or work orders")
	check(world.flower_gifts.active.is_empty() and not world._routes.has("codex") and not world.director.destinations.has("codex"), "finished gesture releases route and transient prop")
	check(not world.flower_gifts.eligible("codex") and not world.flower_gifts.eligible("companion-2"), "resident and village cooldown prevent repeated gifts")
	check(world.local_companion.events.any(func(e):return e.context == "flower_gift" and e.source == "local_rules"), "optional gift line is clearly local authored life")
	world = fixture(); world.local_companion.set_chatter(false)
	world.local_companion._start("flower_gift")
	for tick in range(800):
		world.advance(.05)
		if world.local_companion.kind.is_empty(): break
	check(world.local_companion.events.is_empty(), "muting chatter leaves the gesture silent")
	world = fixture(); world.local_companion._start("flower_gift")
	world.command("codex", {"intent":"stop"})
	check(world.flower_gifts.active.is_empty() and world.local_companion.next_decision-world.local_companion.time >= 119.9, "explicit stop cleans flower and enforces normal quiet period")
	world = fixture(); world.local_companion._start("flower_gift")
	check(world.command("codex", {"intent":"gather_wood","tree_count":1}).ok and world.work.jobs.codex.intent == "gather_wood" and world.flower_gifts.active.is_empty(), "accepted resource work preempts gift without stale route")
	world = fixture(); world.local_companion._start("flower_gift")
	world.local_companion.set_held(true)
	check(world.flower_gifts.active.is_empty() and not world._routes.has("codex"), "conversation or question interrupts gift")
	world = fixture(); world.local_companion._start("flower_gift"); world.activities.gather()
	check(world.flower_gifts.active.is_empty() and world.activities.members.has("codex"), "assembly cancels gift before formation")
	world = fixture(); world.local_companion._start("flower_gift"); world.local_companion.set_enabled(false)
	check(world.flower_gifts.active.is_empty(), "turning off daily life removes gesture")
	world = fixture(); world.local_companion._start("flower_gift")
	check(world.command("human", {"intent":"move","x":Places.point("p_51_0_66_0").x,"y":Places.point("p_51_0_66_0").y}).ok, "human may walk away during gift")
	for tick in range(400): world.advance(.05)
	check(world.flower_gifts.active.is_empty() and not world.local_companion.events.any(func(e):return e.context == "flower_gift"), "distant recipient cancels without a remote delivery or endless chase")
	world = fixture(); world.local_companion._start("flower_gift")
	world._routes.erase("codex") # Simulate a navigation failure, without moving the actor.
	world.advance(.1)
	check(world.flower_gifts.active.is_empty(), "lost route does not count as arrival")
	world = fixture(); world.local_companion.set_enabled(false)
	check(not world.local_companion._start("flower_gift"), "disabled daily life cannot start a flower gesture")
	world = fixture(); world.local_companion._start("flower_gift")
	check(Save.save_world(world,directory), "save during cosmetic gesture")
	var restored := World.new()
	check(Save.load_world(restored,directory).ok and restored.flower_gifts.active.is_empty() and restored.work.jobs.is_empty() and restored._routes.is_empty(), "reload never restores a phantom bouquet, route or job")
	world = fixture(); var actor: Dictionary = world.actors.codex.duplicate(true)
	actor.activity = "local_pick_flower"
	var motion := Motion.new(); motion.advance(.5,{"codex":actor})
	var pose: Dictionary = motion.pose(actor,{},world.actors,{"progress":.5})
	check(pose.frame.begins_with("flower_pick_") and pose.scale.y < 1.0 and pose.fallback.begins_with("pickup_"), "pick pose bends with editable action-frame fallback")
	var actor_before: Dictionary = actor.duplicate(true)
	for tick in range(100): motion.pose(actor,{},world.actors,{"progress":float(tick)/100.0})
	check(actor==actor_before, "presentation never changes resident movement or resources")
	# Real controller/view, fake-model-free: exercise natural selection, not inference.
	var game: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled=false; game.set_process(false); game.view.set_process(false); game.view.sound_enabled=false
	game.world.director.set_all_enabled(false); game.world.advance(80)
	game.world.activities.release_follow("codex");game.world.activities.default_follow_excluded["codex"]=true
	game.world.local_companion.set_enabled(true); game.world.local_companion.rng.seed=5
	game.world.local_companion.last_walk=0
	game.world.local_companion.preferences.weights={"flower_gift":2}
	game.world.local_companion.next_decision=game.world.local_companion.time
	game.world.advance(.1)
	check(game.world.local_companion.kind=="flower_gift", "normal local decision pipeline selects flower behavior")
	var capture := OS.get_environment("HABITAT_CAPTURE_DIR")
	var captured := {}
	for tick in range(800):
		game.world.advance(.05); game.view._process(.05)
		var gift: Dictionary = game.world.flower_gifts.presentation("codex")
		if not capture.is_empty() and not gift.is_empty() and gift.phase in ["picking","bringing","offering"] and not captured.has(gift.phase) and (gift.phase=="bringing" or gift.progress>.4):
			game.view.center=(game.world.point(game.world.actors.human)+game.world.point(game.world.actors.codex))*.5+Vector2(0,-1.5); game.view.zoom=1.35
			if gift.phase == "offering": game.view.say("路边这朵小花，送给你。", "local_rules", "codex")
			game.view.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(capture)
			root.get_texture().get_image().save_png(capture.path_join(gift.phase+".png")); captured[gift.phase]=true
		if game.world.local_companion.kind.is_empty():break
	check(game.links.values().all(func(link):return link._pid==-1) and game.group_links.is_empty(), "complete local gift starts zero model connections")
	if not capture.is_empty(): check(captured.size()==3,"actual viewport captures all three visible gesture stages")
	game.queue_free(); await process_frame
	print("Flower gifts: %s checks, %s"%[checks,"FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
