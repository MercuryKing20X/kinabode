extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var failures:=0
func _initialize()->void:call_deferred("run")
func check(v:bool,label:String)->void:
	if not v:failures+=1;push_error(label)
func total(w:RefCounted,item:String)->int:
	var n:int=w.storage.count(item)
	for actor in w.actors.values():n+=int(actor.carry.get(item,0))
	return n
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(directory)
	preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase");w.director.set_all_enabled(false)
	# Authored planted crops mature by real engine elapsed time, not inventory grants.
	w.advance(50000)
	var before:Dictionary={};var expected:Dictionary={}
	for plot in w.farms.farm_plots("farm.home"):
		check(w.farms.stage(plot)=="mature","real crop matured")
		expected[plot.crop_id]=int(expected.get(plot.crop_id,0))+int(w.farms.crops[plot.crop_id].yield)
		var seed:String="seed."+str(plot.crop_id);expected[seed]=int(expected.get(seed,0))+1
	for item in expected:before[item]=total(w,item)
	check(preload("res://scripts/save_store.gd").save_world(w,directory),"real matured crops persisted")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide();w.director.set_all_enabled(false)
	for i in range(8):await process_frame
	var plot:Dictionary=w.farms.farm_plots("farm.home")[0]
	game.view.follow_player=false;game.view.center=w.point(plot)
	var at:Vector2=game.view.screen(w.point(plot))
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
	check(game.farm_panel.visible,"real field click opens farm")
	for i in range(1200):
		if not w.work.jobs.has("human"):break
		game._process(.1);game.view._process(.1)
		if i%40==0:await process_frame
	check(await UI.click(self,game.farm_panel.harvest_button),"real harvest all button")
	var maximum:=0;var deposited:=false
	for i in range(2500):
		game._process(.1);game.view._process(.1)
		maximum=maxi(maximum,w.life.item_count(w.actors.human.carry))
		for event in w.work.events:maximum=maxi(maximum,int(event.get("backpack_count",0)))
		if w.storage.count("turnip")>int(before.get("turnip",0)) or w.storage.count("tomato")>int(before.get("tomato",0)):deposited=true
		if not w.farms.active("human") and not w.work.jobs.has("human"):break
		if i%40==0:await process_frame
	for item in expected:check(total(w,item)==int(before[item])+int(expected[item]),"real full harvest conserved "+item)
	check(maximum==0 and deposited and not w.farms.active("human"),"human harvest commits directly to warehouse with zero carried units and completes")
	check(w.farms.farm_plots("farm.home").all(func(p):return int(p.harvests)==1),"all twelve plots harvested once")
	print("Storage harvest input failures=",failures," max=",maximum," deposited=",deposited)
	game.queue_free();await process_frame;quit(1 if failures else 0)
