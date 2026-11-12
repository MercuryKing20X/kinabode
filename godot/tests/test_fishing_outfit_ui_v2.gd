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
func mouse(pos:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down and button==MOUSE_BUTTON_LEFT else 0;event.position=pos;event.global_position=pos;root.push_input(event,true);await process_frame
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"));root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	for mode in ["showcase","standard"]:
		OS.set_environment("HABITAT_OPENING","legacy" if mode=="showcase" else "standard")
		var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(temp.path_join(mode));assert(Opening.apply(w,w.library,mode).ok);w.intelligence.activate_presets();w.hunger.start()
		var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();await process_frame;await process_frame
		var hud:Node=game.island_hud
		var assignments:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
		for actor_id in assignments:
			hud.refresh();await process_frame;await process_frame
			check(await UI.click(self,hud.appearance_buttons[actor_id]),mode+" actual wardrobe button "+actor_id)
			var wardrobe:Node=hud.wardrobe;await process_frame;await process_frame
			check(wardrobe.visible and wardrobe.selected_actor==actor_id,mode+" wardrobe binds resident "+actor_id)
			var matches:Array=UI.descendants(wardrobe.grid).filter(func(n):return n is Button and n.get_meta("work_id","")==assignments[actor_id])
			check(matches.size()==1,mode+" target appearance exists "+assignments[actor_id])
			if matches.is_empty():continue
			var target:Button=matches[0];var scroll:ScrollContainer=wardrobe.grid.get_parent()
			for attempt in range(30):
				if scroll.get_global_rect().has_point(target.get_global_rect().get_center()):break
				await mouse(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
			check(await UI.click(self,target) and wardrobe.selected_work==assignments[actor_id],mode+" actual appearance selection "+actor_id)
			var confirm:Array=UI.descendants(wardrobe).filter(func(n):return n is Button and n.text=="确定")
			check(confirm.size()==1 and await UI.click(self,confirm[0]) and w.actors[actor_id].appearance_id==assignments[actor_id],mode+" actual confirm changes selected appearance "+actor_id)
		var target:Dictionary={}
		for spot in w.fishing.nearby_shores("human",32):
			var p:=Vector2(spot.position[0],spot.position[1]);game.view.center=p;game.view.follow_player=false;game.view.zoom=1
			if p.distance_to(w.point(w.actors.human))>=15 and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():target=spot;break
		check(not target.is_empty(),mode+" reachable shore from far away")
		if not target.is_empty():
			await mouse(game.view.screen(Vector2(target.position[0],target.position[1])))
			check(w._routes.has("human"),mode+" shore mouse click starts real route")
			for step in range(3000):
				game._process(.1);game.view._process(.1)
				if not w._routes.has("human"):break
			check(not w.fishing.shore("human").is_empty(),mode+" actual host arrives at shore")
			check(await UI.click(self,game.actions_button),mode+" mouse opens action dock")
			var fish_buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
			check(fish_buttons.size()==1 and await UI.click(self,fish_buttons[0]),mode+" mouse selects fish")
			check(await UI.click(self,game.action_dock.all_fishers),mode+" mouse invites all")
			check(await UI.click(self,game.action_dock.popup.get_ok_button()),mode+" mouse confirms")
			for step in range(1200):
				game._process(.1);game.view._process(.1)
				if assignments.keys().all(func(id):return w.work.jobs.get(id,{}).get("phase") in ["fish_cast","fish_wait","fish_bite","fish_reel"]):break
			for actor_id in assignments:
				check(w.work.jobs.get(actor_id,{}).get("intent")=="fish" and game.view.fishing_renderer.animation_texture(game.view,w.actors[actor_id])!=null,mode+" selected AI appearance fishes with own atlas "+actor_id)
		check(game.links.values().all(func(link):return link._pid<=0),mode+" no model processes")
		game.queue_free();await process_frame;await process_frame
	print("Fishing nondefault wardrobe mouse v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
