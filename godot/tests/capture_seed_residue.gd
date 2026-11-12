extends "res://tests/capture_route_latched.gd"
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);await process_frame;await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();game.world.director.set_all_enabled(false)
	if OS.get_environment("SEED_DARK")=="1":
		await click_button(game.dark_ui.entry_button)
		var go:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="出发")
		await click_button(go[0])
		for i in range(10000):
			await step()
			if game.world.actors.human.region_id=="dark" and not game.world._routes.has("human") and not game.dark_ui.boat_pending:break
	var w:RefCounted=game.world
	w.actors.human.carry={"seed.pumpkin":1}
	var store:Script=preload("res://scripts/save_store.gd")
	assert(store.save_world(w,OS.get_environment("HABITAT_DATA_DIR")))
	assert(store.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).ok)
	game.view.center=w.point(w.actors.human);game.view.follow_player=false;game.view.zoom=1.25;game.view._process(.01);await shot("seed-residue-loaded")
	if OS.get_environment("SEED_BASELINE").is_empty():
		await click_button(game.actions_button)
		var b:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="收进背包")
		if b.size()!=1:failed=true
		else:await click_button(b[0])
		await shot("seed-stowed")
		if w.loaded("human") or (w.actors.human.carry.size()!=1 or int(w.actors.human.carry.get("seed.pumpkin",0))!=1):failed=true
		await route("seed-stowed-long",15,true)
		store.save_world(w,OS.get_environment("HABITAT_DATA_DIR"));store.load_world(w,OS.get_environment("HABITAT_DATA_DIR"))
		if w.loaded("human") or (w.actors.human.carry.size()!=1 or int(w.actors.human.carry.get("seed.pumpkin",0))!=1):failed=true
	FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "));print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)
