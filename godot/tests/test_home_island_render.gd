extends SceneTree
const Renderer=preload("res://scripts/home_island_renderer.gd")
const Text=preload("res://scripts/localization.gd")
var results:Array=[]
var failed:=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func game_for(manifest:String,directory:String)->Node:
	OS.set_environment("HABITAT_OPENING","legacy");OS.set_environment("HABITAT_DATA_DIR",directory)
	var g:Node=load("res://scenes/main_v3.tscn").instantiate();g.world=preload("res://scripts/world_state.gd").new(manifest);root.add_child(g)
	g.save_enabled=false;g.set_process(false);g.view.set_process(false);g.view.sound_enabled=false;g.island_hud.set_process(false);g.chat.hide();g.world.director.set_all_enabled(false)
	return g
func bench(g:Node,at:Vector2,label:String)->void:
	g.view.center=at;g.view.follow_player=false
	for i in range(5):g.view.queue_redraw();await process_frame
	var elapsed:=0.0
	for i in range(30):
		var start:int=Time.get_ticks_usec();g.view.queue_redraw();RenderingServer.force_draw(false);await process_frame
		elapsed+=(Time.get_ticks_usec()-start)/1000.0
	results.append({"label":label,"average_frame_ms":elapsed/30.0,"frames":30,"center":[at.x,at.y],"size":[root.size.x,root.size.y]})
func capture(g:Node,name:String)->void:
	var out:String=OS.get_environment("HABITAT_ISLAND_CAPTURE")
	if out.is_empty() or DisplayServer.get_name()=="headless":return
	g.view.queue_redraw();await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
func run()->void:
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var old:Node=game_for("res://content/migrations/home-island-v1/world.json",base.path_join("old"));await process_frame;await process_frame
	await bench(old,Vector2(81,55),"before-north")
	old.queue_free();await process_frame
	var g:Node=game_for("res://content/home-v3/world.json",base.path_join("merged"));await process_frame;await process_frame
	Renderer.draw_counts={"land":0,"decor":0}
	await bench(g,Vector2(81,55),"after-north")
	check(Renderer.draw_counts.land==0 and Renderer.draw_counts.decor==0,"offscreen southern land and decoration culled completely")
	await bench(g,Vector2(81,182),"after-south")
	check(Renderer.draw_counts.land>0,"visible southern geometry actually drawn")
	await bench(g,Vector2(81,55),"after-return-north")
	for language in ["zh_CN","en"]:
		TranslationServer.set_locale(language);Text.events.changed.emit()
		for size_value in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=size_value;await process_frame
			g.view.center=Vector2(81,142);g.view.follow_player=false
			await capture(g,language+"-"+str(size_value.x)+"-bridge")
			g.view.center=Vector2(79,180)
			await capture(g,language+"-"+str(size_value.x)+"-south")
			for camera in [Vector2(81,198),Vector2(33,205),Vector2(129,205),Vector2(81,245)]:
				g.view.center=camera
				await capture(g,language+"-"+str(size_value.x)+"-road-"+str(int(camera.x))+"-"+str(int(camera.y)))
	var out:String=OS.get_environment("HABITAT_ISLAND_CAPTURE")
	if not out.is_empty():
		var file:=FileAccess.open(out.path_join("performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"results":results,"failed":failed},"  "))
	print("home island render metrics ",JSON.stringify(results))
	g.queue_free();await process_frame;quit(1 if failed else 0)
