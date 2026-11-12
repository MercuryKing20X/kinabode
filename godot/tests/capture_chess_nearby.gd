extends SceneTree
const Opening = preload("res://scripts/world_opening.gd")
const Save = preload("res://scripts/save_store.gd")
const Jobs = preload("res://tests/barbecue_fixture.gd")
const Text = preload("res://scripts/localization.gd")
var game: Node
var failures: Array = []
var record: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func click_at(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = at; e.global_position = at
		root.push_input(e, true)
		await process_frame
func click(control: Control) -> void: await click_at(control.global_position + control.size / 2)
func choose(picker: OptionButton, index: int) -> void:
	await click(picker)
	var popup := picker.get_popup()
	await click_at(Vector2(popup.position) + Vector2(popup.size.x * .5, (index + .5) * float(popup.size.y) / picker.item_count))
func key_button(node: Node, key: String) -> BaseButton:
	if node is BaseButton and node.get_meta("chess_key", "") == key: return node
	for child in node.get_children():
		var found := key_button(child, key)
		if found != null: return found
	return null
func jieqi_button(node: Node, key: String) -> BaseButton:
	if node is BaseButton and node.get_meta("jieqi_key", "") == key: return node
	for child in node.get_children():
		var found := jieqi_button(child, key)
		if found != null: return found
	return null
func shot(name: String) -> void:
	var output := OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func finish() -> void:
	record.failures = failures
	var output := OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not output.is_empty():
		var prefix := "far-" if OS.get_environment("CHESS_ENTRY_PHOTOS_ONLY")=="1" else "matrix-"
		var f := FileAccess.open(output.path_join(prefix + record.case_id + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(record, "  "))
	print("MATRIX ", JSON.stringify(record))
	quit(1 if not failures.is_empty() else 0)

func run() -> void:
	var dir := OS.get_environment("HABITAT_DATA_DIR")
	var opening := OS.get_environment("CHESS_OPENING")
	var location := OS.get_environment("CHESS_LOCATION")
	var state := OS.get_environment("CHESS_STATE")
	if not dir.contains("youqi-test-") or opening not in ["standard", "showcase"] or location not in ["home", "moon"] or state not in ["normal", "unbuilt", "justbuilt", "allhungry", "partialhungry", "gomoku", "jieqi"]: quit(1); return
	record = {"case_id": opening + "-" + location + "-" + state, "opening": opening, "location": location, "state": state, "results": {}}
	root.size = Vector2i(1280, 800); root.content_scale_size = Vector2i.ZERO
	var w = preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	w.residents.provision(w); w.library = preload("res://scripts/character_library.gd").new(); w.library.configure(dir)
	check(Opening.apply(w, w.library, opening).ok, "opening applied")
	w.intelligence.activate_presets(); w.hunger.start(); w.director.set_all_enabled(false)
	var site: Dictionary = w.leisure.sites["play.gomoku"]
	if state == "unbuilt" and opening == "showcase":
		site.complete = false; site.invested = 0; site.erase("preset_origin")
	if state != "unbuilt" and not site.complete:
		if not w.leisure.chess_space_clear(site, w.leisure.art(site).recreation):
			var placed: Dictionary = {}
			for y in range(5, 110, 2):
				for x in range(5, 110, 2):
					placed = w.leisure.place("play-gomoku", Vector2(x + .5, y + .5))
					if placed.ok: break
				if placed.ok: break
			check(placed.get("ok", false), "place legal chess foundation")
			if placed.get("ok", false): site = w.leisure.sites[placed.site_id]
		var trees: Array = w.objects.values().filter(func(o): return o.kind == "tree" and o.status == "mature")
		for tree in trees:
			if w.storage.count("wood") >= w.leisure.cost(site): break
			var gathered: bool = Jobs.job(w, "human", {"intent":"gather_wood", "target_id":tree.id, "tree_count":1})
			if gathered: print("gathered ", tree.id, " storage=", w.storage.count("wood"))
		if not w.actors.human.carry.is_empty(): check(Jobs.job(w, "human", {"intent":"store"}), "deposit before construction")
		var construction: Dictionary = w.command("human", {"intent":"build_facility", "target_id":site.id})
		print("construction ", construction, " wood=", w.storage.count("wood"), " cost=", w.leisure.cost(site))
		if construction.ok: Jobs.wait_actor(w, "human")
		check(construction.ok and site.complete, "real table construction")
		if not w.actors.human.carry.is_empty(): check(Jobs.job(w, "human", {"intent":"store"}), "deposit remaining carry")
	if state in ["gomoku", "jieqi"]:
		var started: Dictionary = w.gomoku.begin_host(site.id, "codex", true, "local", "normal") if state == "gomoku" else w.jieqi.start("codex", 197, "standard", site.id)
		check(started.ok, "existing match started")
		for i in range(2500):
			w.advance(.1)
			if (w.gomoku.sessions[site.id].phase if state == "gomoku" else w.jieqi.phase) != "arriving": break
		if state == "gomoku":
			var match_state: Dictionary = w.gomoku.sessions[site.id]
			check(match_state.phase == "playing", "gomoku seated")
			check(w.command("human", {"intent":"gomoku_move", "site_id":site.id, "match_id":match_state.id, "revision":match_state.revision, "x":7, "y":7}).ok, "gomoku first move")
			w.gomoku.pause(match_state, "fixture")
		else: check(w.jieqi.phase == "playing", "jieqi seated")
	if state in ["allhungry", "partialhungry"]:
		for i in range(15000):
			w.advance(.1)
			var ranks: Array = w.standard.config.companions.map(func(id): return w.hunger.rank(id))
			if (state == "allhungry" and ranks.all(func(rank): return rank >= 3)) or (state == "partialhungry" and ranks.any(func(rank): return rank >= 3) and ranks.any(func(rank): return rank < 3)): break
		record.hunger_before_save = w.standard.config.companions.map(func(id): return {"id":id,"rank":w.hunger.rank(id)})
		var hungry_count: int = record.hunger_before_save.filter(func(item): return item.rank >= 3).size()
		check(hungry_count == 4 if state == "allhungry" else hungry_count > 0 and hungry_count < 4, "fixture hunger state reached by advance")
	var p: Vector2 = w.point(site) + Vector2(0, 2) if location == "home" else Vector2(w.map_anchor("moon.lookout")[0], w.map_anchor("moon.lookout")[1])
	w.actors.human.position = [p.x, p.y]
	check(Save.save_world(w, dir), "fixture save")
	OS.set_environment("HABITAT_OPENING", opening)
	game = load("res://scenes/main_v3.tscn").instantiate(); root.add_child(game); game.save_enabled = false
	for i in range(30): await process_frame
	check(game.world.opening_id == opening, "main loaded correct opening")
	check(game.world.leisure.sites[site.id].complete == site.complete, "main loaded table state")
	game.chat.hide(); game.view.show_region("home"); game.view.center = game.world.point(game.world.leisure.sites[site.id]); game.view.zoom = 1
	for i in range(5): await process_frame
	await nearby_check(site.id)

func nearby_check(site_id: String) -> void:
	game.set_process(false);game.view.set_process(false)
	game.island_hud.refresh_context()
	check(game.island_hud.chess_button.is_visible_in_tree(),"nearby button visible")
	if OS.get_environment("CHESS_ENTRY_PHOTOS_ONLY")!="1":await shot("nearby-"+record.opening)
	var origin: Vector2=game.world.point(game.world.leisure.sites[site_id])
	var far:=origin+Vector2(10,0)
	var screen: Vector2=game.view.screen(far)
	await click_at(screen)
	for i in range(600):
		game._process(.1);game.view._process(.1);await process_frame
		if game.world.point(game.world.actors.human).distance_to(origin)>5:break
	game.island_hud.refresh_context()
	check(not game.island_hud.chess_button.is_visible_in_tree(),"far button hidden")
	await shot("far-"+record.opening)
	if OS.get_environment("CHESS_ENTRY_PHOTOS_ONLY")=="1":finish();return
	var rect: Rect2=game.view.leisure_renderer.rect(game.view,game.world.leisure.sites[site_id])
	await click_at(rect.position+Vector2(rect.size.x*.5,rect.size.y*.25))
	record.pending_chess=game.pending_chess.duplicate(true)
	for i in range(600):
		game._process(.1);game.view._process(.1);await process_frame
		if game.chess_choice.visible:break
	check(game.chess_choice.visible,"table click routes to choice")
	await shot("nearby-return-"+record.opening)
	finish()
