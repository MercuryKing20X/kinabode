extends "res://tests/test_ingredient_native_input.gd"
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	var plot:Dictionary={}
	for p in game.world.farms.farm_plots("farm.home"):
		if game.world.farms.stage(p) in ["growing","seedling"]:plot=p;break
	await click_world(game.world.point(plot));await process_frame
	var opened:bool=game.farm_panel.visible and await UI.click(self,game.farm_panel.helpers_button)
	var dialog:Node=null
	for child in game.get_children():
		if child.get_script()==load("res://scripts/farm_invitation.gd"):dialog=child
	var ids:Array=dialog.checks.keys() if dialog!=null else []
	print("BEFORE_HELPERS ",ids)
	if dialog!=null:
		await capture("before-only-two",game.world.point(plot))
		await UI.click(self,dialog.checks.codex);await UI.click(self,dialog.get_ok_button())
		var accepted:String=game.farm_panel.note.text
		var stock:Dictionary=game.world.storage.saved().duplicate(true)
		for i in range(8):game.world.advance(.5)
		var result:Dictionary={"shown_ids":ids,"accepted_message":accepted,"helper_order":game.world.farms.orders.get("codex",{}),"helper_route":game.world._routes.has("codex"),"unchanged_stock":game.world.storage.saved()==stock}
		var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("before.json"),FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close();print("BEFORE_NO_TARGET ",result)
	game.queue_free();await process_frame;quit(0 if opened else 1)
