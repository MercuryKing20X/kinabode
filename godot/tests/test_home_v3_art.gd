extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var lib=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");world.library=lib;world.residents.provision(world);world.director.set_all_enabled(false)
	check(preload("res://scripts/world_opening.gd").apply(world,lib).ok,"showcase initialized")
	var view=preload("res://scripts/island_v3_view.gd").new();view.world=world;view.library=lib;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.hide();root.add_child(view);view.set_process(false);view.sound_enabled=false
	var layout:Dictionary=world.catalog.regions.home.layout
	check(layout.art_props.size()>=200,"authored whole-island scenery clusters")
	check(layout.solid_props.size()==14,"well, board, four planters and eight lamp bases assigned to World")
	check(not world.walkable("home",Vector2(world.map_anchor("well")[0],world.map_anchor("well")[1])),"well collision enforced by World")
	check(view.terrain.cache_builds==1,"continuous terrain cached once")
	for tick in range(600):world.advance(.1);view.terrain.prepare(view.ground_config)
	check(view.terrain.cache_builds==1,"600 advances do not rebuild static polygons")
	var old:Dictionary=view.ground_config.duplicate(true);old.well[0]+=.1;view.terrain.prepare(old)
	check(view.terrain.cache_builds==2,"content change invalidates terrain cache")
	check(view.boardwalk.get_width()==224 and view.boardwalk.get_height()==96,"original floor crop reused at native pixels")
	check(view.props.textures.has("unlit_fire"),"cold campfire uses no flame layer")
	for home in layout.residential:
		if home.owner_id.is_empty():continue
		var art:Dictionary=world.objects[home.site_id].blueprint.artwork
		check(view._house_size(world.objects[home.site_id])==Vector2(art.width,art.height),"original native house pixels: "+home.owner_id)
	for id in ["play.chess.bench","play.dock.bench.south","play.dock.bench.west"]:
		check(world.host_command("npc.mira",{"intent":"use_facility","target_id":id}).ok,"bench is a real seat "+id)
		var sat:=false
		for tick in range(3000):
			world.advance(.1)
			if world.actors["npc.mira"].activity=="seated":sat=true;break
		check(sat,"resident actually arrived and sat "+id)
		world.command("npc.mira",{"intent":"stop"})
	print("Home v3 art: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
