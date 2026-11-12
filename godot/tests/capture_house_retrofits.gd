extends SceneTree
const Study=preload("res://scripts/house_retrofit_study.gd")
var output:String
var records:Array=[]
func _initialize()->void:call_deferred("run")
func capture(name:String,meta:Dictionary)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();assert(image.save_png(output.path_join(name))==OK)
	meta.merge({"file":name,"actual_viewport":true,"pixels":[image.get_width(),image.get_height()],"world_pixels_per_tile":32,"integer_scale":1})
	records.append(meta)
func run()->void:
	output=OS.get_environment("HABITAT_HOUSE_CAPTURE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	root.content_scale_size=Vector2i.ZERO
	var scene:=Study.new();root.add_child(scene)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size
		for time in ["afternoon","night"]:
			scene.period=time;scene.queue_redraw()
			await capture("street-"+time+"-"+str(size.x)+"x"+str(size.y)+".png",{"kind":"street","period":time,"houses":5})
	scene.queue_free();await process_frame
	root.size=Vector2i(1280,800)
	for id in ["human","gentle","curious","lively","quiet"]:
		var pair:=Study.new();pair.comparison_id=id;root.add_child(pair)
		await capture("compare-"+id+"-master.png",{"kind":"master_pair","house":id,"left":"unchanged original master","right":"full-master derivative"})
		pair.queue_free();await process_frame
	root.size=Vector2i(2560,800)
	var left:=SubViewport.new();left.size=Vector2i(1280,800);left.world_2d=World2D.new();left.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(left)
	var right:=SubViewport.new();right.size=Vector2i(1280,800);right.world_2d=World2D.new();right.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(right)
	var game:Node=load("res://scenes/main.tscn").instantiate();left.add_child(game)
	game.save_enabled=false;game.set_process(false);game.set_process_input(false);game.set_process_unhandled_input(false);game.view.set_process(false);game.view.set_process_unhandled_input(false);game.view.sound_enabled=false;game.view.follow_player=false;game.view.clock=0
	for routine in game.world.director.routines.values():routine.set_enabled(false)
	for child in game.get_children():
		if child is CanvasLayer:child.hide()
	game.atlas.hide();game._house_scenario();assert(game.world.objects["home.house.01"].stage_index==5)
	var before:Array=game.world.actors.human.position.duplicate()
	game.view.center=game.world.point(game.world.objects["home.house.01"])+Vector2(0,-3);game.view.zoom=1;game.view.queue_redraw()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var legacy:=left.get_texture().get_image();legacy.save_png(output.path_join("existing-island-original-1280x800.png"))
	records.append({"file":"existing-island-original-1280x800.png","actual_viewport":true,"pixels":[1280,800],"kind":"unaltered original renderer reference","world_pixels_per_tile":32,"house_display_pixels":[352,370]})
	# Normalize only the comparison preview to native master pixels, avoiding the
	# original renderer's 352x370 display stretch. Keep an unaltered reference too.
	game.view.hide()
	var native:Node=preload("res://scripts/house_comparison_native_view.gd").new()
	native.world=game.world;native.library=game.view.library;native.font=game.view.font;native.sound_enabled=false
	left.add_child(native);native.set_process(false);native.set_process_unhandled_input(false)
	native.center=game.view.center;native.zoom=1;native.queue_redraw()
	var street:=Study.new();right.add_child(street)
	for index in range(2):
		var display:=TextureRect.new();display.texture=(left if index==0 else right).get_texture();display.position=Vector2(index*1280,0);display.size=Vector2(1280,800);display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;root.add_child(display)
	await capture("compare-existing-island-five-houses.png",{"kind":"live_subviewports","left":"original island, screenshot-only native house scale","right":"five retrofit houses","subviewports":[[1280,800],[1280,800]],"no_saved_image_compositing":true,"house_pixel_scale_both_sides":1,"legacy_house_stretch_removed_only_in_comparison":true})
	assert(game.world.actors.human.position==before)
	var pids:Dictionary={}
	for id in game.links:
		var pid:Variant=game.links[id].get("_pid");pids[id]=pid;assert(pid==null or int(pid)<=0)
	var file:=FileAccess.open(output.path_join("viewport-records.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"records":records,"real_model_calls":0,"model_pids":pids,"temporary_data":true,"human_moved":false},"  "))
	game.queue_free();await process_frame;print("Eleven real house-retrofit viewport screenshots completed.");quit()
