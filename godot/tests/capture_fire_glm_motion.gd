extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
var w:RefCounted
var view:Node2D
var label:Label
var output:String
var files:Array=[]
func _initialize()->void:call_deferred("run")
func step(delta:float)->void:
	w.advance(delta);view.clock+=delta
	var running:Dictionary={};var moves:Dictionary={};var gaits:Dictionary={}
	for id in w.actors:running[id]=w.is_running(id);moves[id]=w.motion_state(id);gaits[id]=w.intelligence.gait(id)
	view.motion.advance(delta,w.actors,running,moves,gaits);view.update_ambience();view.queue_redraw()
func wait(id:String)->void:
	for tick in range(6000):
		if not w._routes.has(id) and not w.work.jobs.has(id):return
		step(.05)
	assert(false,"world movement timed out")
func move(id:String,point:Vector2)->void:
	assert(w.command(id,{"intent":"move","x":point.x,"y":point.y}).ok);wait(id)
func shot(id:String,art:String,direction:String,delta:Vector2,prefix:String)->void:
	var origin:Vector2=w.point(w.actors[id]);var dest:Vector2=origin+delta*2
	assert(w.segment_clear("home",origin,dest) and w.walkable("home",dest))
	assert(w.command(id,{"intent":"move","x":dest.x,"y":dest.y}).ok)
	step(.12);assert(w.motion_state(id).moving and w.actors[id].facing==direction)
	label.text="实际移动画面 · "+art+" · "+direction+" · "+prefix
	view.queue_redraw();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var name:String=prefix+"-"+art+"-"+direction+".png"
	var img:Image=root.get_texture().get_image();assert(img.get_size()==Vector2i(1280,800) and img.save_png(output.path_join(name))==OK)
	files.append({"file":name,"actor_id":id,"appearance":art,"direction":direction,"moving":true,"position":w.actors[id].position.duplicate()})
	wait(id);move(id,origin)
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	output=OS.get_environment("HABITAT_FIRE_GLM_SCREENSHOTS");assert(not output.is_empty())
	DisplayServer.window_set_size(Vector2i(1280,800));root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(temp)
	assert(Opening.apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.director.set_all_enabled(false)
	view=preload("res://scripts/island_v3_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.follow_player=false;view.zoom=2
	var overlay:=CanvasLayer.new();root.add_child(overlay);label=Label.new();label.position=Vector2(15,15);label.add_theme_font_override("font",view.font);label.add_theme_font_size_override("font_size",20);overlay.add_child(label)
	var center:Array=w.map_anchor("plaza.center");var start:=Vector2(center[0]-5,center[1]+10);view.center=start+Vector2(0,-1)
	assert(w.walkable("home",start))
	var choices:Array=[{"name":"left","v":Vector2.LEFT},{"name":"right","v":Vector2.RIGHT},{"name":"up","v":Vector2.UP},{"name":"down","v":Vector2.DOWN}]
	var original:Dictionary=w.library.artworks["ai-glm"].duplicate(true)
	var pairs:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/glm_legacy_direction_hashes.json"))
	assert(w.assign_appearance("npc.nora","ai-glm"));move("npc.nora",start)
	var before:Dictionary=original.duplicate(true)
	for pair in pairs.pairs:
		var old:Variant=before.frames[pair.left];before.frames[pair.left]=before.frames[pair.right];before.frames[pair.right]=old
	w.library.artworks["ai-glm"]=before;w.library.textures.clear()
	for entry in choices:await shot("npc.nora","ai-glm",entry.name,entry.v,"before")
	w.library.artworks["ai-glm"]=original;w.library.textures.clear()
	for entry in choices:await shot("npc.nora","ai-glm",entry.name,entry.v,"after")
	move("npc.nora",start+Vector2(8,0))
	var people:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
	for id in people:
		assert(w.assign_appearance(id,people[id]));move(id,start)
		for entry in choices.slice(0,2):await shot(id,people[id],entry.name,entry.v,"worn")
		var plots:Array=w.catalog.regions.home.layout.residential.filter(func(plot):return plot.owner_id==id)
		if not plots.is_empty():
			assert(w.command(id,{"intent":"enter","target_id":plots[0].site_id}).ok);wait(id)
	var file:=FileAccess.open(output.path_join("appearance-viewports.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"actual_viewport":true,"size":[1280,800],"files":files,"before_source":"reversed corrected GLM pairs in temporary memory only","player_files_read_or_written":false},"  "));file.close()
	print("Actual appearance viewports: ",files.size());view.queue_free();overlay.queue_free();await process_frame;quit()
