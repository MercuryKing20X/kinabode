extends "res://tests/capture_route_latched.gd"
func settle()->void:
	for i in range(2500):
		game._process(.1);game.view._process(.1);await process_frame
		if not game.world.work.jobs.has("human") and not game.world._routes.has("human"):return
	failed=true
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world;var f:RefCounted=w.farms;var farm:String="farm.home"
	f.farms[farm].manager_id="human"
	w.actors.human.carry={"seed.pumpkin":1}
	var save:Script=preload("res://scripts/save_store.gd")
	assert(save.save_world(w,OS.get_environment("HABITAT_DATA_DIR")));assert(save.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).ok)
	var plot:Dictionary=f.farm_plots(farm)[0];plot.crop_id="pumpkin";plot.watered=true;plot.planted_at=f.clock-f.crops.pumpkin.seconds-1
	var chest:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991};var crop_yield:int=f.crops.pumpkin.yield
	# Warehouse has no full-box fault; real harvest remains the original yield.
	game.view.center=w.point(plot);game.view.follow_player=false;game.view.zoom=1.25
	await click(game.view.screen(w.point(plot)))
	await click_button(game.farm_panel.plot_button);await settle();await shot("harvest-full-box-left-seed")
	if int(w.actors.human.carry.get("seed.pumpkin",0))+int(chest.items.get("seed.pumpkin",0))!=2 or w.loaded("human") or not w.actors.human.get("pocketed",false) or int(w.actors.human.carry.get("pumpkin",0))+int(chest.items.get("pumpkin",0))!=crop_yield:failed=true
	records.append({"label":"partial-full-chest","carry":w.actors.human.carry.duplicate(),"chest_count":w.life.item_count(chest.items),"capacity":chest.capacity,"pocketed":w.actors.human.get("pocketed",false)})
	game.farm_panel.refresh()
	await click_button(game.farm_panel.more_toggle)
	var take:Array=UI.descendants(game.farm_panel).filter(func(n):return n is Button and n.text=="取一捆")
	var before:int=w.life.item_count(w.actors.human.carry)
	if take.size()==1:await click_button(take[0]);await settle()
	await shot("pocketed-seed-take")
	records.append({"label":"take-with-pocketed-seed","before":before,"after":w.actors.human.carry.duplicate(),"feedback":game.farm_panel.note.text})
	if int(w.actors.human.carry.get("pumpkin",0))!=2 or w.life.item_count(w.actors.human.carry)>20 or w.life.item_count(w.actors.human.carry)<=before:failed=true
	FileAccess.open(output.path_join("farm.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "));print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)
