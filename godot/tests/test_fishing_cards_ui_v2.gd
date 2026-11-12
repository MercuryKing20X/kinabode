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
		for i in range(3000):
			game._process(.1)
			if w.fishing.fish.values().filter(func(f):return f.location in ["pending","storage"]).size()==5:break
		var pending:Array=w.fishing.fish.values().filter(func(f):return f.location in ["pending","storage"])
		check(pending.size()==5,"five real independent fish caught")
		game.chat.hide();game.island_hud.refresh();await process_frame;await process_frame
		var hud:Node=game.island_hud
		var controls:Array=UI.descendants(hud.notifications)
		for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=dimensions;hud.notices_signature="";hud.refresh();await process_frame;await process_frame
			var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
			for control in UI.descendants(hud.notifications):
				if control is Button and control.visible:check(bounds.encloses(control.get_global_rect()),"fish card controls fit viewport "+str(dimensions)+" "+control.text+" "+str(control.get_global_rect()))
		root.size=Vector2i(1280,800);hud.notices_signature="";hud.refresh();await process_frame;await process_frame
		controls=UI.descendants(hud.notifications)
		check(controls.filter(func(n):return n is Button and n.text=="放入渔场").size()==3,"at most three fish cards visible")
		check(controls.any(func(n):return n is Button and n.text=="还有 2 条"),"extra fish appear in badge")
		var title:Array=controls.filter(func(n):return n is Button and n.text.contains("钓到"))
		check(not title.is_empty() and await UI.click(self,title[0]),"actual mouse opens caught fish message")
		check(game.fishing_panel.visible and game.fishing_panel.selected_fish in w.fishing.fish and w.fishing.fish[game.fishing_panel.selected_fish].location in ["pending","storage"],"fishery details expose real pending fish")
		var close:Array=UI.descendants(game.fishing_panel).filter(func(n):return n is Button and n.text=="收起")
		check(not close.is_empty() and await UI.click(self,close[0]),"actual mouse closes fishery")
		hud.refresh();await process_frame;await process_frame
		check(hud.expanded_notice.is_empty() and hud.notifications.visible,"closing fishery restores fish messages")
		title=UI.descendants(hud.notifications).filter(func(n):return n is Button and n.text.contains("钓到"))
		check(not title.is_empty() and await UI.click(self,title[0]),"original message can open again")
		close=UI.descendants(game.fishing_panel).filter(func(n):return n is Button and n.text=="收起")
		check(await UI.click(self,close[0]),"close reopened fishery")
		hud.refresh();await process_frame;await process_frame
		controls=UI.descendants(hud.notifications)
		var later:Array=controls.filter(func(n):return n is Button and n.text=="稍后")
		check(not later.is_empty() and await UI.click(self,later[0]),"actual mouse defers one pending fish")
		check(w.fishing.fish.values().filter(func(f):return f.location in ["pending","storage"]).size()==5,"deferring retains exact fish instances")
		var more:Array=UI.descendants(hud.notifications).filter(func(n):return n is Button and n.text.begins_with("还有 "))
		check(not more.is_empty() and await UI.click(self,more[0]),"badge reopens deferred catches")
		controls=UI.descendants(hud.notifications)
		var release:Array=controls.filter(func(n):return n is Button and n.text=="放生")
		check(not release.is_empty() and await UI.click(self,release[0]),"actual mouse releases selected fish")
		check(w.fishing.fish.values().filter(func(f):return f.location in ["pending","storage"]).size()==4,"release removes exactly one instance")
		var stock:Array=UI.descendants(hud.notifications).filter(func(n):return n is Button and n.text=="放入渔场")
		check(not stock.is_empty() and await UI.click(self,stock[0]),"actual mouse stocks one fish")
		check(w.fishing.fish.values().filter(func(f):return f.location in ["pending","storage"]).size()==3,"one-click placement moves exactly one fish")
		var all:Array=UI.descendants(hud.notifications).filter(func(n):return n is Button and n.text=="全部放入渔场")
		check(not all.is_empty() and await UI.click(self,all[0]),"actual mouse stocks remaining fish")
		check(w.fishing.fish.size()==4 and w.fishing.fish.values().all(func(f):return f.location not in ["pending","storage"]),"all remaining unique fish placed without duplication")

	game.queue_free();await process_frame
	print("Fishing quick cards mouse v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
