extends SceneTree
const Helper=preload("res://tests/test_barbecue_v2.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var helper:=Helper.new();var world:RefCounted=helper.fresh(temp);world.intelligence.activate_presets()
	var view:Node=preload("res://scripts/island_v3_view.gd").new();view.world=world;view.library=world.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.ambience_enabled=false;view.update_ambience()
	var actor:Dictionary=world.actors["npc.nora"];view.follow_player=false;view.zoom=2.0;view.center=world.point(actor)
	var root_path:String=ProjectSettings.globalize_path("res://..");var output:String=root_path.path_join("production/evidence/sound-v2")
	var frame_root:String=root_path.path_join("tmp/sound-v2-gesture-frames")
	assert(DirAccess.make_dir_recursive_absolute(output)==OK);assert(DirAccess.make_dir_recursive_absolute(frame_root)==OK)
	for id in ["ai-gpt","ai-deepseek","ai-claude","ai-glm"]:
		actor.appearance_id=id;actor.activity="gesture_wave";actor.facing="down"
		var folder:String=frame_root.path_join(id);assert(DirAccess.make_dir_recursive_absolute(folder)==OK)
		for n in range(8):
			view.motion.states[actor.id]={"phase":0.0,"step":0.0,"blink_until":0.0,"activity_age":float(n)*.1}
			view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
			assert(view.gesture_symbol_bounds.has(id+":"+str(world.library.artworks[id].revision)+":down_0"))
			var image:Image=root.get_texture().get_image();assert(not image.is_empty())
			var size:Vector2i=image.get_size();var crop:Rect2i=Rect2i(size.x/2-130,size.y/2-300,260,330)
			assert(Rect2i(Vector2i.ZERO,size).encloses(crop));var region:Image=image.get_region(crop)
			assert(region.save_png(folder.path_join("wave-%02d.png"%n))==OK)
			if n==3:assert(region.save_png(output.path_join("gesture-"+id+".png"))==OK)
	view.queue_free();helper.free();await process_frame
	print("Gesture visual fixture: 4 appearances, 8 engine frames each; not real-mouse acceptance")
	quit()
