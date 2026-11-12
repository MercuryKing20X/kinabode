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
	var plot:Dictionary=f.farm_plots(farm)[0];plot.crop_id="pumpkin";plot.watered=true;plot.planted_at=f.clock-f.crops.pumpkin.seconds-1
	var chest:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991};var crop_yield:int=f.crops.pumpkin.yield
	# Warehouse has no full-box fault; real harvest remains the original yield.
	game.view.center=w.point(plot);game.view.follow_player=false;game.view.zoom=1.25
	await click(game.view.screen(w.point(plot)))
	await click_button(game.farm_panel.plot_button);await settle();await shot("harvest-full-box-left-seed")
	if w.actors.human.carry!={"seed.pumpkin":1} or w.loaded("human") or not w.actors.human.get("pocketed",false):failed=true
	records.append({"label":"partial-full-chest","carry":w.actors.human.carry.duplicate(),"chest_count":w.life.item_count(chest.items),"capacity":chest.capacity,"pocketed":w.actors.human.get("pocketed",false)})
	game.farm_panel.refresh()
	await click_button(game.farm_panel.more_toggle)
	var picker:OptionButton=game.farm_panel.crop_picker
	await click(picker.get_global_rect().get_center())
	var popup:PopupMenu=picker.get_popup();var index:=0
	for n in range(picker.item_count):
		if str(picker.get_item_metadata(n))=="pumpkin":index=n
	await click(Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*popup.size.y/popup.item_count))
	await click_button(game.farm_panel.plot_button);await settle();print("PLANT_FEEDBACK ",game.farm_panel.note.text," crop=",game.farm_panel.crop_id());await shot("leftover-seed-planted")
	if not w.actors.human.carry.is_empty() or plot.crop_id!="pumpkin":failed=true
	records.append({"label":"reuse-leftover","carry":w.actors.human.carry.duplicate(),"crop":plot.crop_id})
	FileAccess.open(output.path_join("farm.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "));print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)
