extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World=preload("res://scripts/world_state.gd")
const Endpoint=preload("res://scripts/read_endpoint.gd")
var checks:=0
var failed:=false
var game: Node
var output: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_ATLAS_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
	await process_frame
	var world: RefCounted=game.world
	world.director.set_all_enabled(false)
	var actors: Dictionary=world.actors.duplicate(true)
	var objects: Dictionary=world.objects.duplicate(true)
	var revision: int=world.revision
	var endpoint: Node=game.endpoint
	var token: String=endpoint.bindings.keys()[0]
	var bound: String=endpoint.bindings[token]
	var request: Dictionary={"session":endpoint.session,"token":token,"expires":Time.get_unix_time_from_system()+30,"operation":"read_map","query":{}}
	check(endpoint.handle(request).self_actor_id==bound,"map endpoint respects exact bound identity")
	request.token="invalid";check(endpoint.handle(request).get("error")=="unauthorized","map endpoint rejects invalid token")
	request.token=token;request.session="old";check(endpoint.handle(request).get("error")=="stale_session","map endpoint rejects stale session")
	var page: Dictionary=world.read_map("codex",{"limit":1})
	check(page.ok and page.total==3 and page.regions.size()==1,"bounded catalog contains all registered islands")
	check(world.read_map("codex",{"limit":1,"offset":1,"revision":page.revision}).ok,"map page continues with catalog version")
	check(world.read_map("codex",{"offset":1}).get("error")=="stale_map","map continuation requires version")
	var detail: Dictionary=world.read_map("codex",{"region_id":"pine"})
	check(detail.region.availability=="preview_only" and not detail.region.travel_available,"unplayable island is honestly labelled")
	check(detail.region.has("land") and detail.region.has("zones") and detail.region.pack.has("version"),"detail exposes shape, uses and pack metadata")
	check(not detail.capabilities.hot_reload and not detail.capabilities.cross_island_travel,"no false extension or travel capability")
	for args in [{"actor_id":"human"},{"limit":true},{"limit":101},{"offset":-1},{"offset":NAN},{"revision":1},{"region_id":""}]:
		check(not world.read_map("codex",args).ok,"bad map query rejects "+str(args))
	check(world.read_map("codex",{"region_id":"missing"}).get("error")=="unknown_region","unknown detail rejects")
	check(world.read_map("missing").get("error")=="unknown_resident","unknown caller rejects")
	detail.region.land.clear()
	check(not world.catalog.regions.pine.land.is_empty(),"map result cannot mutate source")
	check(world.actors==actors and world.objects==objects and world.revision==revision,"map reads are observational")
	game._toggle_atlas(true)
	check(game.atlas.visible and game.atlas.panel.visible,"map opens with controls")
	check(game.atlas.island_list.get_child_count()==3,"island list follows catalog")
	for id in world.catalog.regions:
		check(game.atlas.map_rect().has_point(game.atlas.screen_position(game.atlas._region_center(id))),"first overview includes "+id)
	await shot("overview")
	game.atlas.island_list.get_child(1).pressed.emit()
	check(game.atlas.selected_region=="pine" and game.atlas.view_button.disabled,"list selects preview without travel")
	check(game.atlas.detail.get_parsed_text().contains("尚未开放"),"detail explains preview status")
	await shot("island-detail")
	game.atlas.overview()
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;var polygon: PackedVector2Array=world.catalog.polygon(world.catalog.regions.moon)
	var triangles: PackedInt32Array=Geometry2D.triangulate_polygon(polygon)
	var inside: Vector2=(polygon[triangles[0]]+polygon[triangles[1]]+polygon[triangles[2]])/3
	click.position=game.atlas.screen_position(Vector2(world.catalog.regions.moon.origin[0],world.catalog.regions.moon.origin[1])+inside)
	game.atlas._unhandled_input(click)
	check(game.atlas.selected_region=="moon" and game.atlas.visible,"map click selects island and keeps atlas open")
	var old_center: Vector2=game.atlas.center;var old_scale: float=game.atlas.scale_factor
	game._toggle_atlas(false);game._toggle_atlas(true)
	check(game.atlas.center==old_center and game.atlas.scale_factor==old_scale and game.atlas.selected_region=="moon","reopening preserves viewpoint and selection")
	check(world.actors==actors and world.objects==objects and world.work.jobs.is_empty(),"all map browsing preserves residents and resources")
	check(game.links.values().all(func(link):return link._pid==-1),"browsing starts no inference")
	var pack: Dictionary=world.catalog._json("res://content/examples/player-island.json")
	check(world.catalog.validate_pack(pack).is_empty(),"existing extension example remains valid")
	# Loaded-catalog fixture only; no new runtime import operation is implied.
	var extra: Dictionary=pack.regions[0].duplicate(true);extra.origin=[7300,7000]
	world.catalog.regions[extra.id]=extra;world.catalog.region_packs[extra.id]={"id":pack.id,"version":pack.version}
	check(world.read_map("codex").total==4,"additional loaded island automatically appears")
	check(world.read_map("codex",{"revision":page.revision}).get("error")=="stale_map","catalog change invalidates old pages")
	game.atlas.open();game.atlas.overview()
	check(game.atlas.island_list.get_child_count()==4 and game.atlas.map_rect().has_point(game.atlas.screen_position(game.atlas._region_center(extra.id))),"overview dynamically fits distant extension")
	await shot("extended-catalog")
	world.catalog.regions.erase(extra.id);world.catalog.region_packs.erase(extra.id)
	game.atlas.open();game.atlas.focus("home")
	await shot("home")
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.position=game.atlas.map_rect().get_center()+Places.point("p_40_20")
	var before: Vector2=game.atlas.world_position(wheel.position);game.atlas._unhandled_input(wheel)
	check(before.distance_to(game.atlas.world_position(wheel.position))<.001,"zoom remains anchored under cursor")
	world.command("codex",{"intent":"move","x":Places.point("p_54_0_44_0").x,"y":Places.point("p_54_0_44_0").y});world.advance(.1)
	check(world.read_map("codex",{"revision":page.revision}).ok,"resident movement never invalidates map catalog")
	var job_count: int=world.work.jobs.size();var routes: Dictionary=world._routes.duplicate(true)
	game.atlas.nearby();game.atlas.focus("pine")
	check(world.work.jobs.size()==job_count and world._routes==routes,"map does not preempt accepted movement")
	world.command("codex",{"intent":"stop"})
	game.atlas.focus("home")
	var home_click:=InputEventMouseButton.new();home_click.button_index=MOUSE_BUTTON_LEFT;home_click.pressed=true
	home_click.position=game.atlas.screen_position(Vector2(world.catalog.regions.home.origin[0]+51,world.catalog.regions.home.origin[1]+44))
	game.atlas._unhandled_input(home_click)
	check(game.atlas.visible and game.atlas.selected_point.distance_to(Places.point("p_51_44"))<.001,"home click selects exact local point without moving")
	var before_action: Dictionary=world.actors.duplicate(true)
	game.atlas.view_button.pressed.emit()
	check(not game.atlas.visible and game.view.center.distance_to(Places.point("p_51_44"))<.001 and world.actors==before_action,"explicit view opens chosen home location and changes only camera")
	game._toggle_atlas(true)
	var original_bounds: Array=world.catalog.manifest.bounds.duplicate()
	world.catalog.manifest.bounds=[100,200,400,500];game.atlas.center=Vector2(-5,900);game.atlas.clamp_center()
	check(game.atlas.center==Vector2(100,700),"pan bounds follow manifest rather than fixed ocean size")
	world.catalog.manifest.bounds=original_bounds
	root.size=Vector2i(960,640)
	await process_frame;await process_frame
	game.atlas.nearby();await shot("small")
	var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;game._input(escape)
	check(not game.atlas.visible and not game.atlas.panel.visible,"escape closes atlas and its controls")
	game.queue_free();await process_frame
	print("Archipelago map: %s checks, %s"%[checks,"FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
func shot(name: String) -> void:
	if output.is_empty():return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var bounds:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	check(bounds.encloses(game.atlas.panel.get_global_rect()),"sidebar fits viewport "+name)
	check(game.atlas.panel.get_global_rect().encloses(game.atlas.view_button.get_global_rect()),"detail action remains inside panel "+name)
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
