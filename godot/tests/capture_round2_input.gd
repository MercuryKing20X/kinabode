extends "res://tests/capture_dark_expansion.gd"
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	game.dark_ui.set_process(false)
	d.life.fireside.sources()[0].items.wood=30
	w.assign_appearance("companion-2","ai-claude",false,false)
	await click_button(game.gathering_button);await click_button(game.follow_ui.all_box);await click_button(game.follow_ui.menu.get_ok_button())
	await click_button(game.dark_ui.entry_button)
	var go:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="出发")
	await click_button(go[0]);await settle();await shot("01-follow-bridge")
	if not d.here():failed=true
	await click_button(game.dark_ui.fire_button)
	w.director.set_all_enabled(true)
	for target in [Vector2(42,79),Vector2(69,58),Vector2(85,78)]:
		await walk_to(target);game.view.center=w.point(w.actors.human)
		await shot("dark-before-"+str(target.x))
		if d.torch.remaining<=0:await click_button(game.dark_ui.fire_button)
		print("RELIC_TARGET ",target," hit=",game.view.hit(game.view.screen(target))," light=",d.discoveries.illuminated(target))
		await click(game.view.screen(target));await settle()
		await shot("found-"+str(target.x))
	for item in d.discoveries.config.objects:
		if item.id in ["bell","page","button"]:records.append({"id":item.id,"found":item.id in d.discoveries.found})
	for item in d.discoveries.config.objects:
		if not item.has("tag"):continue
		await walk_to(d.p(item.position));game.view.center=w.point(w.actors.human)
		if d.torch.remaining<=0:await click_button(game.dark_ui.fire_button)
		for frame in range(240):game._process(.1);game.view._process(.1);await process_frame
		if d.torch.remaining<=0:await click_button(game.dark_ui.fire_button)
		await shot("own-"+item.tag)
		print("OWN_STATE ",item.id," revealed=",d.companions.revealed)
		print("OWN_HIT ",item.id," ",game.view.hit(game.view.screen(d.p(item.position))))
		await click(game.view.screen(d.p(item.position)));await settle()
	var flies:Array=d.discoveries.fireflies()
	for i in range(mini(3,flies.size())):
		await walk_to(d.p(flies[i].position));game.view.center=w.point(w.actors.human)
		if d.torch.remaining<=0:await click_button(game.dark_ui.fire_button)
		print("FLY_TARGET ",flies[i].id," hit=",game.view.hit(game.view.screen(d.p(flies[i].position))))
		await click(game.view.screen(d.p(flies[i].position)));await settle()
	await shot("fireflies-collected")
	await walk_to(Vector2(116,-75));game.view.center=w.point(w.actors.human)
	await click(game.view.screen(Vector2(116,-75)))
	if is_instance_valid(game.dark_ui.menu):
		var light:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="点亮灯台 · 6 木材")
		if light.size()==1:await click_button(light[0]);await settle()
	await shot("new-heather-beacon")
	await walk_to(Vector2(52,-80));game.view.center=w.point(w.actors.human)
	print("STAR_TARGET ",w.actors.human.position," hit=",game.view.hit(game.view.screen(Vector2(52,-80))))
	await click(game.view.screen(Vector2(52,-80)))
	if is_instance_valid(game.dark_ui.menu):
		for i in range(120):game._process(.1);game.view._process(.1);await process_frame
		var stars:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="看星星")
		if stars.size()==1:await click_button(stars[0]);await settle()
	for i in range(160):game._process(.1);game.view._process(.1);await process_frame
	await shot("star-cliff")
	records.append({"star_participants":d.discoveries.seated.duplicate()})
	await click(game.view.screen(w.point(w.actors.human)+Vector2(3,0)));await settle()
	await walk_to(d.p(d.config.walking_connection.dark_end))
	for i in range(50):game._process(.1);game.dark_ui._process(.1);game.view._process(.1);await process_frame
	await click_button(game.actions_button)
	var place:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="摆放萤火虫罐")
	if place.size()==1:await click_button(place[0])
	await shot("jar-mainland-placed")
	await click_button(game.actions_button)
	var reclaim:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="收回萤火虫罐")
	if reclaim.size()==1:await click_button(reclaim[0])
	await shot("jar-reclaimed")
	var resume:String=OS.get_temp_dir().path_join("youqi-test-round2-resume")
	preload("res://scripts/save_store.gd").save_world(w,resume)
	records.append({"failed":failed,"found":d.discoveries.found.duplicate(),"flies":d.discoveries.catches.duplicate(),"jar":w.actors.human.carry.get("firefly.jar",0),"beacons":d.beacons.duplicate(),"stars":d.discoveries.star_days.duplicate()})
	if d.discoveries.found.size()<3 or int(w.actors.human.carry.get("firefly.jar",0))!=1 or d.discoveries.star_days.is_empty():failed=true
	FileAccess.open(output.path_join("round2.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "));print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)
