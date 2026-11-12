extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func click_at(pos:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.position=pos;e.global_position=pos;root.push_input(e,true);await process_frame
func capture(name:String)->void:
	var output:=OS.get_environment("HABITAT_DIRECT_GRILL_CAPTURE")
	if output.is_empty():return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"standard").ok);w.intelligence.activate_presets();w.hunger.start()
	assert(preload("res://scripts/save_store.gd").save_world(w,dir))
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();await process_frame;await process_frame
	w.actors.human.appearance_id="suit-hulk"
	game.view.center=w.point(w.objects["home.house.01"]);game.view.follow_player=false;await process_frame
	await click_at(game.view.screen(w.point(w.objects["home.house.01"])))
	check(game.house_panel.visible,"native house panel opens")
	check(not UI.descendants(game.house_panel).any(func(n):return n is Button and n.text.contains("一键建好")),"retired build-all is absent from player UI")
	check(preload("res://scripts/host_build_all.gd").apply(w).ok,"explicit test-only completed-site fixture")
	game.house_panel.hide()
	var target:Dictionary={}
	for spot in w.fishing.nearby_shores("human",32):
		var p:=Vector2(spot.position[0],spot.position[1]);game.view.center=p;game.view.follow_player=false;game.view.zoom=1
		if p.distance_to(w.point(w.actors.human))>=15 and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():target=spot;break
	check(not target.is_empty(),"reachable distant shore")
	if target.is_empty():quit(1);return
	await click_at(game.view.screen(Vector2(target.position[0],target.position[1])))
	for i in range(3000):
		game._process(.1);game.view._process(.1)
		if not w._routes.has("human"):break
	check(not w.fishing.shore("human").is_empty(),"mouse route arrives")
	check(await UI.click(self,game.actions_button),"mouse opens actions")
	var buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
	check(not buttons.is_empty() and await UI.click(self,buttons[0]),"mouse opens fishing")
	check(await UI.click(self,game.action_dock.popup.get_ok_button()),"mouse starts solo fishing")
	for i in range(3000):
		game._process(.1);game.view._process(.1)
		if w.fishing.fish.values().any(func(f):return f.owner_id=="human" and f.location=="storage"):break
	var stored:Array=w.fishing.fish.values().filter(func(f):return f.owner_id=="human" and f.location=="storage")
	var fish:Dictionary=stored[0].duplicate(true) if not stored.is_empty() else {};check(not fish.is_empty(),"one real stored catch")
	if fish.is_empty():quit(1);return
	var journal:Dictionary=w.journal.saved().duplicate(true);var fish_count:int=w.fishing.fish.size()
	check(w.journal.summary("human").discovered>0,"actual first catch appears in journal")
	game.island_hud.notices_signature="";game.island_hud.refresh();await process_frame;await process_frame
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions;game.island_hud.notices_signature="";game.island_hud.refresh();await process_frame;await process_frame
		var rect:=Rect2(Vector2.ZERO,Vector2(dimensions))
		for control in UI.descendants(game.island_hud.notifications):
			if control is Button and control.visible:check(rect.encloses(control.get_global_rect()),"fish card fits "+str(dimensions))
		await capture("fish-card-"+str(dimensions.x))
	root.size=Vector2i(1280,800);game.island_hud.notices_signature="";game.island_hud.refresh();await process_frame;await process_frame
	var actions:Array=UI.descendants(game.island_hud.notifications).filter(func(n):return n is Button and n.text=="直接烧烤")
	check(not actions.is_empty() and await UI.click(self,actions[0]),"mouse chooses grill on fish card")
	var dialogs:Array=game.get_children().filter(func(n):return n is ConfirmationDialog and n.title=="选择营火" and n.visible)
	check(dialogs.size()==1 and await UI.click(self,dialogs[0].get_ok_button()),"mouse selects camp")
	for i in range(4000):
		game._process(.1);game.view._process(.1)
		if not w.fishing.fish.has(fish.id):break
	check(not w.fishing.fish.has(fish.id),"same fish leaves pending after actual walk")
	check(w.fishing.fish.size()==fish_count-1 and w.journal.saved()==journal,"exact one fish consumed; journal retained")
	var life:RefCounted=w.barbecues["home.barbecue"]
	check(life.fireside.state.get("current",{}).get("fish",{}).get("id")==fish.id,"same fish ID on fire")
	var panels:Array=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_panel.gd") and n.visible)
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions;await process_frame;await process_frame
		await capture("call-companion-"+str(dimensions.x))
	root.size=Vector2i(1280,800);await process_frame;await process_frame
	check(not panels.is_empty() and await UI.click(self,panels[0].invite_button),"mouse clicks call")
	var invites:Array=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_invitation.gd") and n.visible)
	check(not invites.is_empty() and await UI.click(self,invites[0].checks.codex) and await UI.click(self,invites[0].checks["npc.mira"]) and await UI.click(self,invites[0].get_ok_button()),"mouse invites two companions")
	for i in range(1500):
		game._process(.1);game.view._process(.1)
		if life.fireside.state.current.eaters.has("codex") and life.fireside.state.current.eaters.has("npc.mira"):break
	check(life.fireside.state.current.eaters.has("codex") and life.fireside.state.current.eaters.has("npc.mira") and "human" not in life.fireside.state.current.eaters,"both invited companions eat")
	game.view.follow_player=false;game.view.center=w.point(life.station)+Vector2(3,0);game.island_hud.refresh()
	await capture("two-companions-ate")
	print("Direct grill mouse: ",checks," checks failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
