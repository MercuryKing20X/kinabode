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
	f.tick();check(w.standard.board_completed.is_empty(),"initial world has no invented completion times")
	check(f.build_first(),"real first camp built without free materials");f.tick()
	check(w.standard.board_completed.has("fire"),"actual completion timestamp recorded")
	var plot:Dictionary=w.farms.farm_plots("farm.home")[0]
	check(f.job({"intent":"plant","target_id":plot.id,"crop_id":"turnip"}),"real seed planting")
	f.tick();var rows:Array=w.standard.board().filter(func(r):return r.done)
	check(rows.size()==2 and rows[0].id=="farm" and rows[0].completed_at>rows[1].completed_at,"completed entries newest first")
	var saved:Dictionary=w.standard.saved();check(w.standard.valid(saved),"optional bounded completion times valid")
	var old:Dictionary=saved.duplicate(true);old.erase("board_completed");check(w.standard.valid(old),"old four-field opening metadata compatible")
	w.standard.restore(old);f.tick();check(w.standard.board_completed.is_empty(),"reload legacy completed facts never invent dates")
	w.standard.restore(saved);check(w.standard.board_completed==saved.board_completed,"new completion times reload exactly")
	check(Save.save_world(w,dir.path_join("board-save")),"real completed board world saves")
	var reload:=F.new();reload.start(dir.path_join("board-read"))
	var loaded:Dictionary=Save.load_world(reload.w,dir.path_join("board-save"))
	check(loaded.ok and saved.board_completed.keys().all(func(k):return absf(float(reload.w.standard.board_completed.get(k,-1))-float(saved.board_completed[k]))<.001),"full save reload retains genuine completion ordering")
	check(reload.w.point(reload.w.actors.codex).distance_to(w.point(w.actors.codex))<.00001,"reloading does not reapply initial dispersed spawn")
	var bad:Dictionary=saved.duplicate(true);bad.board_completed={"fire":-1};check(not w.standard.valid(bad),"invalid completion time rejected")
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
	game._show_opening_board();await process_frame
	var board:AcceptDialog=game.get_children().filter(func(n):return n is AcceptDialog and n.title.begins_with("告示板"))[0]
	var body:Node=preload("res://tests/barbecue_ui_fixture.gd").descendants(board).filter(func(n):return n is VBoxContainer and n.get_children().filter(func(c):return c is HBoxContainer).size()==4)[0]
	check(body.get_children().filter(func(n):return n is HBoxContainer).size()==4,"four real board rows")
	for row in body.get_children():
		if not row is HBoxContainer:continue
		var b:Button=row.get_children().filter(func(n):return n is Button)[0];check(b.text=="在哪里","every row has location entry");b.pressed.emit()
	check(view.location_highlight_until>view.clock and not view.follow_player,"where focuses and highlights only")
	check(w.actors.human==human and preload("res://tests/backpack_fixture.gd").wood_total(w)==stock,"all board and hover interactions preserve human and items")
	check(w.intelligence.catalog.speech["gentle-happy"].lines.has(w.standard.board_quote()),"all-done quote reuses authored speech unit")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.island_hud.refresh();await process_frame;await process_frame
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.island_hud.residents_panel.get_global_rect()),"wardrobe labelled rows fit "+str(size))
		for id in w.standard.config.companions:
			var button:Button=game.island_hud.appearance_buttons[id]
			check(button.icon!=null and button.get_children().any(func(n):return n is Label and n.text=="外观"),"recognizable icon and visible short text")
	game.queue_free();await process_frame;await create_timer(.2).timeout
	print("Standard polish: ",checks," checks, failed=",failed);quit(1 if failed or f.failed else 0)
