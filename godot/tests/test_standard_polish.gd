extends SceneTree
const F=preload("res://tests/standard_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","standard")
	var f:=F.new();f.start(dir)
	var w:RefCounted=f.w
	for id in w.standard.config.companions:
		check(w.walkable("home",w.point(w.actors[id])) and not w.find_route("human",w.point(w.actors[id])).is_empty(),"spawn reachable "+id)
		for other in w.standard.config.companions:
			if other>id:check(w.point(w.actors[id]).distance_to(w.point(w.actors[other]))>=10,"distinct distant initial lives")
	check(f.build_first(),"real first camp built without free materials");f.tick()
	var plot:Dictionary=w.farms.farm_plots("farm.home")[0]
	check(f.job({"intent":"plant","target_id":plot.id,"crop_id":"turnip"}),"real seed planting")
	check(Save.save_world(w,dir.path_join("board-save")),"real built and planted world saves")
	var reload:=F.new();reload.start(dir.path_join("board-read"))
	var loaded:Dictionary=Save.load_world(reload.w,dir.path_join("board-save"))
	check(loaded.ok and reload.w.standard.ready("home.barbecue") and reload.w.farms.plots[plot.id].crop_id=="turnip","full save reload retains actual camp and planting")
	check(reload.w.point(reload.w.actors.codex).distance_to(w.point(w.actors.codex))<.00001,"reloading does not reapply initial dispersed spawn")
	check(f.wood_audit().conserved and f.food_audit().conserved,"all real materials conserved")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false;await process_frame
	var view:Node=game.view;var human:Dictionary=w.actors.human.duplicate(true);var stock:int=preload("res://tests/backpack_fixture.gd").wood_total(w)
	check(w.catalog.regions.home.layout.cliffs.all(func(c):return not view.visible_cliff(c) if c.id=="north-slope" else view.visible_cliff(c)),"orphan cliff and stairs hidden together only standard")
	for cliff in w.catalog.regions.home.layout.cliffs:
		if not view.visible_cliff(cliff):check(not view.cliff_stones(cliff).is_empty() and view.cliff_stones(cliff).all(func(p):return not w.walkable("home",p)),"unchanged cliff blockers remain visibly marked by original rock sprites")
	var site:Dictionary=w.leisure.sites["play.gomoku"]
	view.hover_id="";check(not view.leisure_renderer.detailed(view,site),"far pending site hides cost")
	view.hover_id=site.id;check(view.leisure_renderer.detailed(view,site),"hover reveals actual cost")
	game.island_hud.refresh_context();check(game.island_hud.context.get_children().any(func(b):return b is Button and b.text.contains("交料/建造")),"hover makes real build entry available")
	game.island_hud.activate_context(site.id);check(game.leisure_panel.visible and game.leisure_panel.site_id==site.id,"context opens exact original construction controller");game.leisure_panel.hide()
	check(w.actors.human==human and preload("res://tests/backpack_fixture.gd").wood_total(w)==stock,"hover and opening the build panel preserve human and items")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.island_hud.refresh();await process_frame;await process_frame
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.island_hud.residents_panel.get_global_rect()),"wardrobe labelled rows fit "+str(size))
		for id in w.standard.config.companions:
			var button:Button=game.island_hud.appearance_buttons[id]
			check(button.icon!=null and button.get_children().any(func(n):return n is Label and n.text=="外观"),"recognizable icon and visible short text")
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("Standard polish: ",checks," checks, failed=",failed);quit(1 if failed or f.failed else 0)
