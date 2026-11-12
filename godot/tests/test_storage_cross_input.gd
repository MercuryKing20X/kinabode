extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const L=preload("res://scripts/localization.gd")
var game:Node
var failures:=0
func _initialize()->void:call_deferred("run")
func check(v:bool,label:String)->void:
	if not v:failures+=1;push_error(label)
func step(delta:float)->void:game._process(delta);game.view._process(delta)
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(directory)
	preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase");w.intelligence.activate_presets()
	# Serialized fixture mirrors a real host-away, companion-held old save.
	# The eight units are moved, never minted; no live actor positions are set.
	check(w.storage.take({"wood":8}).ok,"fixture owns eight genuine units")
	w.actors["companion-2"].carry={"wood":8};w.actors["companion-2"].appearance_id="ai-deepseek";w.actors["companion-2"]["custom_appearance"]=true
	w.actors.human.region_id="dark";w.actors.human.position=w.dark.config.arrival.duplicate()
	check(preload("res://scripts/save_store.gd").save_world(w,directory),"write serialized host-away fixture")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide();w.director.set_all_enabled(false)
	for i in range(8):await process_frame
	var stock:int=w.storage.count("wood")
	for i in range(50):step(.2)
	check(w.storage.count("wood")==stock and int(w.actors["companion-2"].carry.get("wood",0))==8,"different island cannot hand over after reload")
	var bridge:Node=null
	for child in game.get_children():
		if child.get_script()==load("res://scripts/dark_island_ui.gd"):bridge=child
	check(bridge!=null,"actual bridge UI")
	if bridge==null:quit(1);return
	# The visible return route is the bridge on the map, not the home-only entry.
	var home_end:Vector2=w.dark.p(w.dark.config.walking_connection.home_end)
	var home_origin:Array=w.catalog.regions.home.origin;var dark_origin:Array=w.catalog.regions.dark.origin
	var across:Vector2=home_end+Vector2(home_origin[0]-dark_origin[0],home_origin[1]-dark_origin[1])
	game.view.follow_player=false;game.view.center=across-Vector2(0,3)
	var at:Vector2=game.view.screen(across)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
	var reserved_stop:=Vector2.INF
	for i in range(4000):
		if w.deliveries.pending.has("companion-2"):reserved_stop=w.deliveries.visit_slot("companion-2")
		step(.1)
		if w.actors.human.region_id=="home" and w.storage.count("wood")==stock+8:break
		if i%50==0:await process_frame
	check(w.actors.human.region_id=="home" and w.storage.count("wood")==stock+8 and w.actors["companion-2"].carry.is_empty(),"after real bridge return same-island settled handover preserves eight")
	check(reserved_stop.is_finite() and w.point(w.actors["companion-2"]).distance_to(reserved_stop)<=.5 and not w._routes.has("companion-2"),"handover occurs at host")
	print("Storage cross input failures=",failures)
	game.queue_free();await process_frame;quit(1 if failures else 0)
