extends "res://tests/capture_dark_island_input.gd"
## Narrow real-input proof: retained beacon memory, dark-only context, temporary illumination returns black.
var measurements:Array=[]
func image()->Image:
	game.view.queue_redraw();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func luminance(im:Image,at:Vector2)->float:
	var amount:=0.0;var count:=0
	for y in range(-2,3):
		for x in range(-2,3):
			var p:Vector2i=Vector2i(at)+Vector2i(x,y)
			if p.x<0 or p.y<0 or p.x>=im.get_width() or p.y>=im.get_height():continue
			var c:Color=im.get_pixelv(p);amount+=.2126*c.r+.7152*c.g+.0722*c.b;count+=1
	return amount/maxi(1,count)
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");mode="showcase"
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.set_process(false);game.view.set_process(false);await process_frame;await process_frame;tick(.1)
	var w:RefCounted=game.world;var d:RefCounted=w.dark
	if w.actors.human.region_id!="dark":
		if not await voyage(false):finish();return
		await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
		await dark_action(Vector2(44,82),"","点一堆火 · 2 木材")
		await dark_action(Vector2(44,66),"","点一堆火 · 2 木材")
		var area:Dictionary=d.config.areas.filter(func(a):return a.has("beacon"))[0]
		await dark_action(d.p(area.beacon),"dark.beacon."+str(area.id),"点亮灯台 · 6 木材")
	check(w.actors.human.region_id=="dark" and d.fires.size()==2 and d.beacons.size()==1,"current real mouse sequence creates two fires and beacon")
	if w.actors.human.region_id!="dark":finish();return
	check(not game.island_hud.context_signature.contains("interior") and button(game.island_hud.context,"布置小屋")==null,"dark region never exposes room furniture context")
	if await walk(d.p(d.config.camp)+Vector2(0,4)):
		game.island_hud.refresh_context()
		check(game.island_hud.context_signature.contains("light:dark.barbecue") and game.island_hud.context_signature.contains("roast:dark.barbecue") and not game.island_hud.context_signature.contains("home.barbecue") and not game.island_hud.context_signature.contains("moon.barbecue"),"onsite camp context binds exact dark station only")
		await pair("dark-camp-context")
	# Canonical Our Days / home-memory UI: a real click must render retained new kind.
	var popup:PopupMenu=game.handbook_menu.get_popup();var memory_id:=-1
	for i in range(popup.item_count):
		if popup.get_item_metadata(i)=="memories":memory_id=popup.get_item_id(i);break
	check(memory_id>=0,"retained memory handbook entry exists")
	await popup_item(game.handbook_menu,memory_id)
	check(game.memory_panel.visible,"real handbook opens retained memory panel")
	var rows:Array=UI.descendants(game.memory_panel.rows).filter(func(n):return n is Button and n.text.contains("点亮了发光蘑菇林"))
	check(rows.size()==1 and await UI.click(self,rows[0]),"real memory row opens actual beacon event")
	check(game.memory_panel.details.get_parsed_text().contains("一起点亮了发光蘑菇林") and game.memory_panel.details.get_parsed_text().contains("地点：dark") and game.memory_panel.details.get_parsed_text().contains("参与："),"Our Days UI shows actual area, place and real participants")
	await pair("our-days-real-beacon-memory")
	await tap(KEY_ESCAPE)
	if OS.get_environment("DARK_VISIBILITY_MEMORY_ONLY")=="1":finish();return
	# Relight for free using actual camp menu then walk into an unlit shore corridor.
	var wood:int=B.wood_total(w)
	await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
	check(d.torch.remaining>110 and B.wood_total(w)==wood,"real checkpoint owned torch refills free")
	var test_point:=Vector2(84,94);var observation:=Vector2(84,98)
	check(not d.permanent(test_point) and w.walkable("dark",test_point),"pixel probe point is true unlit walkable ground")
	await walk(test_point)
	await camera(observation)
	var camera_before:Vector2=game.view.center;var zoom_before:float=game.view.zoom
	var point_screen:Vector2=game.view.screen(test_point)+Vector2(0,14)
	var lit:Image=await image();var lit_value:float=luminance(lit,point_screen)
	await shot("transient-patch-lit")
	var travel_to:=Vector2(106,95)
	await walk(travel_to)
	await camera(observation)
	var dark:Image=await image();var dark_value:float=luminance(dark,point_screen)
	check(game.view.center.distance_to(camera_before)<.03 and is_equal_approx(game.view.zoom,zoom_before),"real keyboard returns exact camera before comparing same ground pixel")
	check(w.point(w.actors.human).distance_to(test_point)>10 and not d.permanent(test_point),"host truly walks away without creating a permanent source")
	check(lit_value>.03 and dark_value<.025 and dark_value<lit_value*.25,"same formerly torch-lit ground returns opaque near-black after walking away")
	measurements.append({"world_point":[test_point.x,test_point.y],"screen_pixel":[point_screen.x,point_screen.y],"camera":[camera_before.x,camera_before.y],"zoom":zoom_before,"lit_luminance":lit_value,"after_walk_luminance":dark_value,"difference":lit_value-dark_value,"distance_walked":w.point(w.actors.human).distance_to(test_point)})
	await shot("transient-patch-dark-again")
	# Bare and torch radii are read config; screenshots provide actual rendered sample, no direct timer edits.
	check(float(d.config.bare_radius)==2 and float(d.config.torch_radius)==4,"authored personal radii stay two/four tiles")
	check(game.view.dark_renderer.overlay.visible,"fog is active only in real dark region")
	check(game.links.values().all(func(link):return link._pid<=0),"new memory and visibility actions launch no model processes")
	finish()
func finish()->void:
	var file:=FileAccess.open(output.path_join("visibility-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"results":results,"measurements":measurements},"  "));file.close()
	game.queue_free();await process_frame;print("Dark visibility input: ",checks," checks failed=",failed);quit(1 if failed else 0)
