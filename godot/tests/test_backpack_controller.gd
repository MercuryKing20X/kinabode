extends SceneTree
const F = preload("res://tests/cooking_fixture.gd")
const B = preload("res://tests/backpack_fixture.gd")
var game: Node
var output: String
var evidence: Array = []
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func refresh() -> void:
	game._process(.21); game.view._process(.1); game.house_panel.refresh()
func park_companion() -> bool:
	var world: RefCounted = game.world
	var origin: Vector2 = world.point(world.actors.codex)
	for offset in [Vector2(8,-3),Vector2(-8,-3),Vector2(8,3),Vector2(-8,3)]:
		var target: Vector2 = origin+offset
		if world.command("codex",{"intent":"move","x":target.x,"y":target.y}).ok: return F.wait(world,"codex")
	return false
func shot(name: String) -> void:
	refresh(); await process_frame; await process_frame
	if not output.is_empty(): await RenderingServer.frame_post_draw
	var world: RefCounted = game.world
	var anchor: Vector2 = game.view.screen(world.point(world.actors.human))
	check(root.get_visible_rect().has_point(anchor + Vector2(0,-49)*game.view.zoom), "loaded overlay anchor fits viewport " + name)
	check(world.life.item_count(world.actors.human.carry) <= world.work.CARRY_LIMIT, "rendered carry is within authority " + name)
	var record := {"name":name,"size":[root.size.x,root.size.y],"carry":world.actors.human.carry.duplicate(true),"activity":world.actors.human.activity,"position":world.actors.human.position.duplicate(),"wood_total":B.wood_total(world),"stored_wood":{"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.get("wood",0),"carry_limit":world.observe("human").self.carry_limit}
	evidence.append(record)
	if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join(name+".png"))
func pair(name: String) -> void:
	root.size = Vector2i(1280,800); await shot(name+"-1280x800")
	root.size = Vector2i(960,640); await shot(name+"-960x640")
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	output = OS.get_environment("HABITAT_BACKPACK_CAPTURE_DIR")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	var world: RefCounted = game.world
	world.director.set_all_enabled(false); game.view.sound_enabled = false; game.view.follow_player = false
	world.hunger.enabled=false # Isolate twenty-item carry/rendering and conservation.
	game.chat.hide(); game.chat_input.release_focus()
	check(B.wood(world,8) and B.wood_total(world)==24, "actual viewport world harvests eight real trees")
	check(park_companion(), "companion walks clear of shared source for unobscured viewport evidence")
	check(F.job(world,"human",{"intent":"take","target_id":"home.chest.01"}) and world.actors.human.carry.get("wood")==20, "actual UI world loads twenty")
	var origin: Vector2 = world.point(world.actors.human)
	var moving := false
	for offset in [Vector2(-5,0),Vector2(5,0),Vector2(0,5),Vector2(0,-5)]:
		var destination: Vector2 = origin+offset
		if world.command("human",{"intent":"move","x":destination.x,"y":destination.y}).ok:
			world.advance(.1); moving = world._routes.has("human"); break
	check(moving and world.actors.human.activity=="walking", "explicit player move walks with twenty")
	check(absf(world.point(world.actors.human).distance_to(origin)-125.0/32*.1)<.0001, "loaded speed remains exactly 125 pixels per second")
	world.advance(.35)
	game.view.center = world.point(world.actors.human)+Vector2(1,-1); game.view.zoom = 1.7
	game.house_panel.open_site("home.house.01")
	await pair("wood20-walking")
	check(game.house_panel.materials.text.contains("手持 20"), "existing house panel reports actual twenty")
	check(F.wait(world,"human") and world.command("human",{"intent":"store","target_id":"home.chest.01"}).ok, "explicit storage follows walk")
	check(world.actors.human.carry.is_empty() and world.storage.count("wood")==24,"instant warehouse deposit transfers actual twenty without animation")
	await pair("wood20-deposit")
	check(F.wait(world,"human") and world.actors.human.carry.is_empty() and world.storage.count("wood")==24,"all twenty remain in warehouse")
	await pair("wood20-stored")
	game.house_panel.hide()
	for n in range(8): check(F.harvest(world,"turnip"), "real produce for overlay evidence")
	check(world.take_storage_host("turnip",20).ok and world.actors.human.carry.get("turnip")==20, "actual twenty crops use existing picnic overlay")
	game.view.center = world.point(world.actors.human)+Vector2(1,-1)
	await pair("crop20-overlay")
	check(world.deposit_all("human").ok and F.mushroom(world), "put real produce away and forage real mushrooms")
	check(park_companion(), "forager walks clear before host overlay evidence")
	check(world.take_storage_host("mushroom",mini(world.work.carry_space("human"),world.storage.count("mushroom"))).ok,"take actual warehouse mushroom for overlay")
	check(world.actors.human.carry.has("mushroom"), "mushroom overlay uses real inventory")
	game.view.center = world.point(world.actors.human)+Vector2(1,-1)
	await pair("mushroom-overlay")
	check(game.links.values().all(func(link):return link._pid==-1), "no model process launched")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("viewport-state.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"passed":not failed,"captures":evidence},"\t")); file.close()
	game.queue_free(); await process_frame
	print("Backpack controller: %s checks, failed=%s" % [checks,failed]); quit(1 if failed else 0)
