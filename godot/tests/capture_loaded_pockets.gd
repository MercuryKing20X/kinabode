extends "res://tests/capture_route_latched.gd"
const Save=preload("res://scripts/save_store.gd")
func init_game()->void:
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);await process_frame;await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();game.world.director.set_all_enabled(false)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	await init_game()
	if OS.get_environment("LOAD_DARK")=="1":
		await click_button(game.dark_ui.entry_button)
		var go:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="出发")
		await click_button(go[0])
		for i in range(15000):
			await step()
			if game.world.actors.human.region_id=="dark" and not game.world._routes.has("human") and not game.dark_ui.boat_pending:break
	var w:RefCounted=game.world
	w.actors.human.carry={"seed.pumpkin":1};w.actors.human.erase("pocketed")
	w.actors.codex.carry={"tomato":3,"seed.tomato":1};w.actors.codex.erase("pocketed")
	w.hunger.ensure("companion-2");w.hunger.states["companion-2"].elapsed=1600
	w.hunger.ensure("npc.nora");w.hunger.states["npc.nora"].elapsed=600
	w.assign_appearance("companion-2","ai-claude",false,false)
	assert(Save.save_world(w,OS.get_environment("HABITAT_DATA_DIR")))
	game.queue_free();await process_frame;await process_frame
	await init_game();w=game.world
	await shot("loaded-no-operation")
	await route("loaded-human-long",15,true)
	if OS.get_environment("LOAD_TORCH")=="1" and w.actors.human.region_id=="dark":
		var before:int=int(w.dark.life.fireside.available().get("wood",0))
		await click_button(game.dark_ui.fire_button)
		var after:int=int(w.dark.life.fireside.available().get("wood",0))
		records.append({"loaded_seed_torch":w.dark.torch.remaining>0,"cost":before-after,"seed":w.actors.human.carry.get("seed.pumpkin",0)})
		if before-after!=1 or w.dark.torch.remaining<=0:failed=true
	if OS.get_environment("LOAD_COMPANIONS")=="1":
		var origin:Vector2=w.point(w.actors.human)
		var away:Vector2=origin+Vector2(15 if origin.x>w.point(w.actors.codex).x else -15,0)
		game.view.center=origin;game.view.follow_player=false
		await click(game.view.screen(away))
		for i in range(1000):
			await step()
			if not w._routes.has("human"):break
		await click_button(game.gathering_button);await click_button(game.follow_ui.checks.codex);await click_button(game.follow_ui.menu.get_ok_button())
		var frames:=0;var runs:=0;var cols:Dictionary={}
		for i in range(3000):
			await step()
			if w.motion_state("codex").moving:
				frames+=1
				if w.display_running("codex"):runs+=1;cols[game.view.motion.run_column("codex",w.intelligence.gait("codex"))]=true
			if not w._routes.has("codex") and i>20:break
		records.append({"actor":"codex","moving":frames,"run":runs,"columns":cols.keys()})
		if frames==0 or runs!=frames or cols.size()<3:failed=true
		await click_button(game.gathering_button);await click_button(game.follow_ui.checks.codex);await click_button(game.follow_ui.checks["npc.nora"]);await click_button(game.follow_ui.menu.get_ok_button())
		var hungry_frames:=0;var hungry_runs:=0
		for i in range(3000):
			await step()
			if w.motion_state("npc.nora").moving:hungry_frames+=1;hungry_runs+=int(w.display_running("npc.nora"))
			if not w._routes.has("npc.nora") and i>20:break
		records.append({"actor":"npc.nora","rank":w.hunger.rank("npc.nora"),"moving":hungry_frames,"run":hungry_runs})
		if hungry_frames==0 or hungry_runs!=0 or w.hunger.rank("npc.nora")!=2:failed=true
	FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE).store_string(JSON.stringify(trace,"  "))
	print("LOAD_STATE ",w.actors.human.carry," loaded=",w.loaded("human")," white_loaded=",w.loaded("codex")," ",JSON.stringify(records))
	game.queue_free();await process_frame;quit(0 if OS.get_environment("LOAD_BASELINE")=="1" else (1 if failed else 0))
