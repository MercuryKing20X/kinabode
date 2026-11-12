extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func click_at(pos:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.position=pos;e.global_position=pos;root.push_input(e,true);await process_frame
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(temp);assert(Opening.apply(w,w.library,"showcase").ok)
	w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(false)
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false)
	await process_frame;await process_frame
	var target:Dictionary={}
	for spot in w.fishing.nearby_shores("human",32):
		var p:=Vector2(spot.position[0],spot.position[1]);game.view.center=p;game.view.follow_player=false;game.view.zoom=1
		if p.distance_to(w.point(w.actors.human))>=15 and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():target=spot;break
	check(not target.is_empty(),"mouse reachable shore starts at least fifteen tiles away")
	if not target.is_empty():
		await click_at(game.view.screen(Vector2(target.position[0],target.position[1])))
		check(w._routes.has("human"),"real mouse shore click starts World route")
		for i in range(3000):
			game._process(.1)
			if not w._routes.has("human"):break
		check(not w.fishing.shore("human").is_empty(),"mouse route arrives at coast")
		check(await UI.click(self,game.actions_button),"actual mouse opens actions")
		var fish_buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
		check(fish_buttons.size()==1 and await UI.click(self,fish_buttons[0]),"actual fish button opens invitation")
		var dock:Node=game.action_dock
		check(dock.popup.visible and dock.all_fishers.text=="所有人","invitation offers All")
		check(await UI.click(self,dock.all_fishers) and dock.choices.get_children().filter(func(n):return n is CheckButton and n.button_pressed).size()==4,"All selects four companions")
		for id in ["codex","companion-2","npc.mira","npc.nora"]:print("before invite ",id," hunger=",w.hunger.rank(id)," job=",w.work.jobs.get(id,{}).get("intent")," route=",w._routes.has(id)," owned=",w.director.routines[id].owns_route," busy=",game._resident_chat_busy(id))
		check(await UI.click(self,dock.popup.get_ok_button()),"actual confirm starts host and invited fishers")
		print("invitation feedback: ",dock.feedback)
		for id in ["human","codex","companion-2","npc.mira","npc.nora"]:check(w.work.jobs.get(id,{}).get("intent")=="fish","real fishing task "+id)
		check(game.links.values().all(func(link):return link._pid<=0),"no model processes")
	game.queue_free();await process_frame
	print("Fishing invitation mouse v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
