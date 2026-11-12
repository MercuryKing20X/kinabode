extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
var output: String
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func mouse(pos:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down and button==MOUSE_BUTTON_LEFT else 0;event.position=pos;event.global_position=pos;root.push_input(event,true);await process_frame
func shot(game:Node,name:String)->void:
	if output.is_empty():return
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(size);root.size=size;game.island_hud.refresh();game.view.queue_redraw()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var im:Image=root.get_texture().get_image()
		check(im.get_size()==size,"actual viewport size "+name+str(size))
		if im.get_size()==size:im.save_png(output.path_join(name+"-%dx%d.png"%[size.x,size.y]))
	DisplayServer.window_set_size(Vector2i(1280,800));root.size=Vector2i(1280,800);game.island_hud.refresh();await process_frame
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"));output=OS.get_environment("HABITAT_FISH_CAPTURE");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	for mode in ["showcase"]:
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
			var label:String=str(game.library.artworks[assignments[actor_id]].name)
			var matches:Array=UI.descendants(wardrobe.grid).filter(func(n):return n is Button and n.text.begins_with(label))
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
			for frame in range(6):
				game._process(.28);game.view._process(.28)
				await shot(game,"cast-%02d"%frame)
			for step in range(1200):
				game._process(.1);game.view._process(.1)
				if assignments.keys().all(func(id):return w.work.jobs.get(id,{}).get("phase") in ["fish_cast","fish_wait","fish_bite","fish_reel"]):break
			for actor_id in assignments:
				check(w.work.jobs.get(actor_id,{}).get("intent")=="fish" and game.view.fishing_renderer.animation_texture(game.view,w.actors[actor_id])!=null,mode+" selected AI appearance fishes with own atlas "+actor_id)
			await shot(game,"five-fishing")
			var elapsed:=0.0;var next_invite:=0.0;var speech_seen:Dictionary={};var captures:=false;var all_capture:=false
			while elapsed<300.0:
				game._process(.25);game.view._process(.25);elapsed+=.25
				for event in w.director.events:
					if str(event.get("context","")).begins_with("fishing_"):speech_seen[str(event.serial)]=event.duplicate(true)
				if int(elapsed*4)%8!=0:continue
				hud.refresh();await process_frame
				var pending:Array=w.fishing.fish.values().filter(func(f):return f.location=="pending")
				if not pending.is_empty():
					if not captures:await shot(game,"fish-cards");captures=true
					var controls:Array=UI.descendants(hud.notifications)
					var all_buttons:Array=controls.filter(func(n):return n is Button and n.text=="全部放入渔场")
					if not all_buttons.is_empty():
						if not all_capture:await shot(game,"stock-all");all_capture=true
						var accepted:bool=await UI.click(self,all_buttons[0]);if not accepted:print("REJECTED all visible=",hud.notifications.visible," hover=",root.gui_get_hovered_control()," size=",root.size," popup=",game.action_dock.popup.visible)
						check(accepted,"actual player stocks all visible catches")
					else:
						var buttons:Array=controls.filter(func(n):return n is Button and n.text=="放入渔场")
						if not buttons.is_empty():
							var accepted:bool=await UI.click(self,buttons[0]);if not accepted:print("REJECTED one visible=",hud.notifications.visible," hover=",root.gui_get_hovered_control()," size=",root.size," popup=",game.action_dock.popup.visible)
							check(accepted,"actual player stocks a catch")
				if elapsed>=next_invite and elapsed<240 and not w.work.jobs.has("human") and not w._routes.has("human") and w.fishing.held("human").is_empty():
					next_invite=elapsed+12
					if await UI.click(self,game.actions_button):
						var buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
						if not buttons.is_empty() and await UI.click(self,buttons[0]) and await UI.click(self,game.action_dock.all_fishers):check(await UI.click(self,game.action_dock.popup.get_ok_button()),"actual player invites another round")
			var pending:Array=w.fishing.fish.values().filter(func(f):return f.location=="pending")
			for attempt in range(10):
				if pending.is_empty():break
				hud.refresh();await process_frame
				var controls:Array=UI.descendants(hud.notifications);var buttons:Array=controls.filter(func(n):return n is Button and n.text=="全部放入渔场")
				if buttons.is_empty():buttons=controls.filter(func(n):return n is Button and n.text=="放入渔场")
				if buttons.is_empty() or not await UI.click(self,buttons[0]):break
				pending=w.fishing.fish.values().filter(func(f):return f.location=="pending")
			check(pending.is_empty(),"all actual catches stocked by mouse")
			var counts:Dictionary={"human":0,"codex":0,"companion-2":0,"npc.mira":0,"npc.nora":0}
			for fish in w.fishing.fish.values():counts[fish.owner_id]=int(counts.get(fish.owner_id,0))+1
			check(w.fishing.fish.size()==counts.values().reduce(func(a,b):return a+b,0),"fish instances stay unique and conserved")
			var pens:Array=w.fishing.pens.values();pens.sort_custom(func(a,b):return w.fishing.residents_fish(a.id).size()>w.fishing.residents_fish(b.id).size())
			var pen:Dictionary=pens[0];var rect:Rect2=w.catalog.rectangle(pen.rect)
			game.view.center=rect.get_center();game.view.follow_player=false;game.view.zoom=1
			var shore_target:=Vector2.INF
			for radius in [6.0,10.0,14.0,18.0,22.0,26.0]:
				for angle in range(32):
					var point:Vector2=rect.get_center()+Vector2.from_angle(TAU*angle/32.0)*radius
					if w.walkable("home",point) and game.view.hit(game.view.screen(point)).is_empty() and not w.find_route("human",point).is_empty():shore_target=point;break
				if shore_target.is_finite():break
			if shore_target.is_finite():
				await mouse(game.view.screen(shore_target))
				for step in range(3000):
					game._process(.1);game.view._process(.1)
					if not w._routes.has("human"):break
				check(w.point(w.actors.human).distance_to(shore_target)<.05,"actual mouse walks to fishery shoreline")
			else:check(false,"reachable shore near stocked fishery")
			game.view.center=rect.get_center();game.view.follow_player=false
			for frame in range(6):
				game._process(.25);game.view._process(.25)
				await shot(game,"fish-swim-%02d"%frame)
			var report={"seconds":elapsed,"caught_by_actor":counts,"fishing_speech_count":speech_seen.size(),"total_fish":w.fishing.fish.size(),"pending":pending.size(),"unique_ids":w.fishing.fish.keys().size(),"stocked_by_pen":{}}
			for p in pens:report.stocked_by_pen[p.id]=w.fishing.residents_fish(p.id).size()
			if not output.is_empty():var file:=FileAccess.open(output.path_join("simulation.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
			print("FIVE_MINUTE ",JSON.stringify(report))
		check(game.links.values().all(func(link):return link._pid<=0),mode+" no model processes")
		game.queue_free();await process_frame;await process_frame
	print("Fishing five minute capture v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
