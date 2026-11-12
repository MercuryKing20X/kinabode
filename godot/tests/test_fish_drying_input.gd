extends "res://tests/test_ingredient_south_input.gd"
func catch_native()->Dictionary:
	var target:Dictionary={}
	for spot in game.world.fishing.nearby_shores("human",64):
		var at:=Vector2(spot.position[0],spot.position[1]);game.view.center=at;game.view.follow_player=false
		if game.view.hit(game.view.screen(at)).is_empty() and not game.world.find_route("human",at).is_empty():target=spot;break
	if target.is_empty() or not await walk(Vector2(target.position[0],target.position[1])):return {}
	if game.world.fishing.shore("human").is_empty():return {}
	if not await UI.click(self,game.actions_button):return {}
	var fish:Button=named_button(game.action_dock.menu,Text.text("activities.fish"))
	if fish==null or not await UI.click(self,fish):return {}
	if not await UI.click(self,game.action_dock.popup.get_ok_button()):return {}
	for i in range(3000):
		game.world.advance(.2)
		if not game.world.fishing.held("human").is_empty():return game.world.fishing.held("human").duplicate(true)
	return {}
func retained_legacy_drying_flow()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:game.world.actors[pair[0]].appearance_id=pair[1]
	await click_world(game.world.point(game.world.actors.human))
	var built:bool=await gather_wood() and await build_production("produce-fishrack",Vector2(57,226))
	print("NATIVE_FISH_RACK ",built)
	var caught:Dictionary=await catch_native() if built else {}
	print("NATIVE_DRYING_CATCH ",not caught.is_empty())
	var okay:bool=not caught.is_empty()
	if okay:okay=await walk(game.world.ingredients.dry_position())
	var ui:Node=game.get_node("IngredientUI");ui._process(0)
	if okay:okay=await UI.click(self,ui.dry_button)
	if okay:
		okay=not game.world.fishing.fish.has(caught.id) and game.world.ingredients.drying.fish_id==caught.id and game.world.storage.count("dried_fish")==0
	if okay:
		await capture("fish-drying-start")
		var wait:float=float(game.world.ingredients.drying.ready_at)-game.world.forest.clock
		game.world.advance(maxf(0,wait-.1))
		okay=await UI.click(self,ui.dry_button) and game.world.storage.count("dried_fish")==0 and game.world.ingredients.drying.fish_id==caught.id
	if okay:
		game.world.advance(1)
		okay=await UI.click(self,ui.dry_button)
		# Save after the explicit ready click, before the next advance processes it.
		var saved:Dictionary=game.world.ingredients.saved()
		okay=okay and not saved.drying.collect
		okay=okay and preload("res://scripts/save_store.gd").save_world(game.world,OS.get_environment("HABITAT_DATA_DIR"))
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("HABITAT_DATA_DIR").path_join("island-v2.json")))
		var forged:Dictionary=data.duplicate(true);forged.fishing.fish[caught.id]=caught.duplicate(true)
		var control:Dictionary=forged.duplicate(true);control.island_ingredients.drying={}
		okay=okay and preload("res://scripts/save_store.gd")._valid(game.world,control)
		okay=okay and not preload("res://scripts/save_store.gd")._valid(game.world,forged)
		game.queue_free();await process_frame
		game=UI.init_game(self);await process_frame;await process_frame
		game.world.advance(1)
		okay=okay and game.world.storage.count("dried_fish")==0 and not game.world.ingredients.drying.is_empty() and not game.world.ingredients.drying.collect
		ui=game.get_node("IngredientUI");ui._process(0)
		okay=okay and await UI.click(self,ui.dry_button)
		game.world.advance(.2)
		okay=okay and game.world.storage.count("dried_fish")==1 and game.world.ingredients.drying.is_empty() and not game.world.fishing.fish.has(caught.id)
		okay=okay and await UI.click(self,ui.dry_button)
		game.world.advance(.2)
		okay=okay and game.world.storage.count("dried_fish")==1
		await capture("fish-drying-collected")
	print("NATIVE_FISH_DRYING_UNIQUE_RELOAD ",okay)
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("fish-drying-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"built":built,"caught_fish_id":caught.get("id",""),"unique_dried_reload":okay},"  "));f.close()
	game.queue_free();await process_frame;quit(0 if okay else 1)

func run()->void:
	# No new southern racks; retained old drying records remain readable only.
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world
	var before:Dictionary=w.storage.saved().duplicate(true)
	var rejected:Dictionary=w.leisure.place("produce-fishrack",Vector2(57,226))
	var record:Dictionary={"fish_id":"retained-legacy-fish-proof","ready_at":600,"collect":true}
	var valid:bool=w.ingredients.valid({"drying":record})
	w.ingredients.restore({"drying":record})
	var saved:Dictionary=w.ingredients.saved()
	var okay:bool=not rejected.ok and rejected.get("error")=="vacation_only" and valid and saved.drying.fish_id==record.fish_id and not saved.drying.collect and w.storage.saved()==before and not w.fishing.fish.has(record.fish_id)
	game.queue_free();await process_frame
	print("VACATION_NO_NEW_RACK_RETAINED_NO_REPLAY ",okay);quit(0 if okay else 1)
