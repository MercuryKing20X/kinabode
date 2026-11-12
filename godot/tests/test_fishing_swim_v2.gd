extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Fixture=preload("res://tests/fishing_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(temp);assert(Opening.apply(w,w.library,"showcase").ok);w.director.set_all_enabled(false)
	check(w.error.is_empty() and w.fishing.pens.size()==2,"expanded pens validate in real world")
	for p in w.fishing.pens.values():
		var rect:Rect2=w.catalog.rectangle(p.rect)
		for dock in w.catalog.regions.home.layout.dock_surfaces:
			var poly:PackedVector2Array=PackedVector2Array(dock.polygon.map(func(pt):return Vector2(pt[0],pt[1])))
			var corners:PackedVector2Array=PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
			check(Geometry2D.intersect_polygons(poly,corners).is_empty(),"pen avoids every dock and bridge "+p.id+" "+dock.id)
	check(Fixture.coast(w,"human"),"real route reaches sea")
	for n in range(15):
		var entry:Dictionary=Fixture.catch_one(w,"human")
		check(not entry.is_empty() and w.fishing.host_stock_nearest(entry.id).ok,"real unique fish caught and stocked "+str(n))
	check(w.fishing.fish.size()==15,"more than twelve real fish exist")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);await process_frame;await process_frame
	var renderer:RefCounted=game.view.fishing_renderer
	var loot_state:int=w.fishing.rng.state;var saved:Dictionary=w.fishing.saved();var moved:=false;var directions_ok:=true;var inside:=true
	for step in range(250):
		game.view._process(.1)
		for pen in w.fishing.pens.values():
			var fish:Array=w.fishing.residents_fish(pen.id);var rect:Rect2=w.catalog.rectangle(pen.rect);var fit:float=renderer.pen_display_scale(game.view,rect,fish)
			for entry in fish:
				var previous:Vector2=renderer.swimmers.get(entry.id,{}).get("position",Vector2.INF)
				var state:Dictionary=renderer.swim(game.view,entry,rect,fit);var pos:Vector2=state.position;var ext:Vector2=state.extent
				inside=inside and rect.encloses(Rect2(pos-ext,ext*2))
				if previous.is_finite():
					var dx:float=pos.x-previous.x
					if pos.distance_to(previous)>.00001:
						directions_ok=directions_ok and absf(angle_difference(float(state.facing),(pos-previous).angle()))<.001
						if absf(dx)>.00001:directions_ok=directions_ok and (bool(state.flip)==(dx<0))
						moved=true
	check(inside,"entire fish stays within enclosure")
	check(moved and directions_ok,"swimming fish actually move and face horizontal movement")
	check(w.fishing.rng.state==loot_state and w.fishing.saved().fish==saved.fish,"presentation does not alter loot RNG or stored fish")
	var ordered:Array=w.fishing.pens.values();ordered.sort_custom(func(a,b):return w.fishing.residents_fish(a.id).size()>w.fishing.residents_fish(b.id).size())
	var pen:Dictionary=ordered[0];var stored:Array=w.fishing.residents_fish(pen.id);var chosen:Dictionary=stored[0];var position:Vector2=renderer.swimmers[chosen.id].position
	if OS.get_environment("HABITAT_SWIM_FPS")=="1":
		game.view.center=w.catalog.rectangle(pen.rect).get_center();game.view.follow_player=false;game.view.zoom=1;game.view.set_process(true)
		for i in range(15):await process_frame;await RenderingServer.frame_post_draw
		var started:int=Time.get_ticks_usec()
		for i in range(120):await process_frame;await RenderingServer.frame_post_draw
		var elapsed:float=float(Time.get_ticks_usec()-started)/1000000.0
		print("SWIM_FPS ",120.0/elapsed," total_fish=",w.fishing.fish.size()," visible_pen_fish=",stored.size()," elapsed=",elapsed)
		game.view.set_process(false);position=renderer.swimmers[chosen.id].position
	game.view.center=position;game.view.follow_player=false;game.view.zoom=1;await process_frame
	var click:Vector2=game.view.screen(position);var hit:String=game.view.hit(click)
	check(hit.begins_with("fish:"),"real visual hit selects an actual stored fish")
	if hit.begins_with("fish:"):
		for down in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=click;event.global_position=click;root.push_input(event,true);await process_frame
		var selected:String=hit.trim_prefix("fish:")
		check(game.fishing_panel.visible and game.fishing_panel.selected_fish==selected and game.fishing_panel.detail.text.contains(w.actors[w.fishing.fish[selected].owner_id].name) and game.fishing_panel.detail.text.contains("第 %s 天"%w.fishing.fish[selected].caught_day),"mouse click shows exact species, owner and true day")
	var old:Dictionary=saved.duplicate(true)
	for entry in old.fish.values():entry.erase("caught_day")
	check(w.fishing.valid_saved(old,w.actors),"legacy fish without caught day remain valid")
	game.queue_free();await process_frame
	print("Fishing swim v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
