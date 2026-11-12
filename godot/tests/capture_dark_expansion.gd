extends "res://tests/capture_route_latched.gd"
func settle()->void:
	for i in range(4000):
		game._process(.1);game.dark_ui._process(.1);game.view._process(.1);await process_frame
		if not game.world._routes.has("human") and game.world.dark.pending.is_empty() and game.world.dark.discoveries.pending.is_empty() and game.world.dark.phase.is_empty() and not game.dark_ui.boat_pending:return
	failed=true
func walk_to(target:Vector2)->void:
	var w:RefCounted=game.world
	for n in range(160):
		var at:Vector2=w.point(w.actors.human)
		if at.distance_to(target)<2.2:return
		var path:Array=w.find_route("human",target)
		if path.is_empty():failed=true;return
		var next:Vector2=path[0]
		if next.distance_to(at)>7:next=at.move_toward(next,7)
		game.view.center=at;game.view.follow_player=false;game.view.zoom=1.25
		await click(game.view.screen(next));await settle()
	failed=true
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);await process_frame;await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();game.world.director.set_all_enabled(false)
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	game.dark_ui.set_process(false)
	print("LANDING ",w.walkable("dark",Vector2(34,127))," party=",w.actors["companion-2"].position)
	# Explicit disposable old-save fixture, never player inventory or claimed earned materials.
	var source:Dictionary=d.life.fireside.sources()[0];source.items.wood=30
	w.assign_appearance("companion-2","ai-claude",false,false)
	d.fires=[{"id":"legacy-fire-a","position":[44,82]},{"id":"legacy-fire-b","position":[44,66]}]
	var old:Array=d.fires.duplicate(true);var save:Script=preload("res://scripts/save_store.gd")
	if not save.save_world(w,OS.get_environment("HABITAT_DATA_DIR")) or not save.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).ok or d.fires!=old:failed=true
	await click_button(game.dark_ui.entry_button)
	var invite:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="叫伙伴一起去")
	await click_button(invite[0])
	var boxes:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is CheckBox and n.text==w.actors["companion-2"].name)
	await click_button(boxes[0])
	var done:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="选好了")
	await click_button(done[0])
	var go:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="出发")
	if go.size()!=1:failed=true
	else:await click_button(go[0]);await settle()
	print("TRAVEL_STATE ",w.actors.human.region_id," at=",w.actors.human.position," status=",game.status.text," pending=",game.dark_ui.boat_pending)
	if not d.here():failed=true
	await shot("camp-old-fires-preserved")
	await click_button(game.gathering_button);await click_button(game.follow_ui.checks["companion-2"]);await click_button(game.follow_ui.menu.get_ok_button())
	var wood:int=int(d.life.fireside.available().get("wood",0))
	await click_button(game.dark_ui.fire_button)
	if d.torch.remaining<=0 or int(d.life.fireside.available().get("wood",0))!=wood-1 or d.fires!=old:failed=true
	await shot("button-held-torch")
	var remaining:float=d.torch.remaining;await click_button(game.dark_ui.fire_button)
	if d.torch.remaining!=remaining or int(d.life.fireside.available().get("wood",0))!=wood-1:failed=true
	for id in ["cedar","tide"]:
		var area:Dictionary=d.config.areas.filter(func(a):return a.id==id)[0]
		await walk_to(d.p(area.beacon))
		game.view.center=w.point(w.actors.human);await shot(id+"-before")
		var before:int=int(d.life.fireside.available().get("wood",0))
		await click(game.view.screen(d.p(area.beacon)))
		print("BEACON_CLICK ",id," actor=",w.actors.human.position," target=",area.beacon," hit=",game.view.hit(game.view.screen(d.p(area.beacon)))," torch=",d.torch.remaining)
		if not is_instance_valid(game.dark_ui.menu):failed=true;break
		var lights:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="点亮灯台 · 6 木材")
		if lights.size()!=1:failed=true
		else:await click_button(lights[0]);await settle()
		for i in range(40):game._process(.1);game.dark_ui._process(.1);game.view._process(.1);await process_frame
		game.view.center=w.point(w.actors.human);game.view.follow_player=false
		await shot(id+"-after")
		if id not in d.beacons or int(d.life.fireside.available().get("wood",0))!=before-6:failed=true
		records.append({"area":id,"human":w.actors.human.position.duplicate(),"companion":w.actors["companion-2"].position.duplicate(),"companion_region":w.actors["companion-2"].region_id,"lit":id in d.beacons,"wood_cost":before-int(d.life.fireside.available().get("wood",0))})
	if d.fires!=old:failed=true
	await click_button(game.gathering_button);await click_button(game.follow_ui.checks["companion-2"]);await click_button(game.follow_ui.menu.get_ok_button())
	game.world.director.set_all_enabled(true)
	for i in range(150):game._process(.1);game.dark_ui._process(.1);game.view._process(.1);await process_frame
	records.append({"label":"lit-relax","companion_lit":d.permanent(w.point(w.actors["companion-2"])),"activity":w.actors["companion-2"].activity})
	game.world.director.set_all_enabled(false)
	for chest in d.life.fireside.sources():chest.items.erase("wood")
	w.actors.human.carry.erase("wood")
	game._process(121);game.view._process(.1)
	var missing:Dictionary={"before":d.life.fireside.available().get("wood",0)}
	await click_button(game.dark_ui.fire_button)
	missing["remaining"]=d.torch.remaining;missing["after"]=d.life.fireside.available().get("wood",0);missing["message"]=game.status.text
	if d.torch.remaining!=0 or missing.before!=missing.after:failed=true
	records.append(missing);await shot("missing-wood-no-torch")
	var opening:=InputEventMouseButton.new();opening.position=game.handbook_menu.get_global_rect().get_center();opening.global_position=opening.position;opening.button_index=MOUSE_BUTTON_LEFT;opening.pressed=true;opening.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(opening,true);await process_frame
	var popup:PopupMenu=game.handbook_menu.get_popup();var index:=0
	for i in range(popup.item_count):
		if popup.get_item_text(i).contains("地图"):index=i
	await click(Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*popup.size.y/popup.item_count))
	if not game.atlas.visible:failed=true
	else:
		var choices:Array=UI.descendants(game.atlas.panel).filter(func(n):return n is Button and n.text=="黑暗岛")
		if choices.size()==1:await click_button(choices[0])
	await shot("handbook-map-new-light")
	save.save_world(w,OS.get_environment("HABITAT_DATA_DIR"));save.load_world(w,OS.get_environment("HABITAT_DATA_DIR"))
	if d.fires!=old or "cedar" not in d.beacons or "tide" not in d.beacons:failed=true
	FileAccess.open(output.path_join("expansion.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "));print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)
