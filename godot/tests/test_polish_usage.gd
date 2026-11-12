extends SceneTree
const Estimate=preload("res://scripts/autonomy_estimate.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/autonomy.json"))
	var caption:=Estimate.usage_reference(config)
	check(caption.contains("实测均值8993") and caption.contains("medium，2回合") and caption.contains("179860") and caption.contains("Ultra档未实测"),"actual medium sample is labelled accurately, never represented as an Ultra measurement")
	var changed: Dictionary=config.duplicate(true);changed.measured_usage.average_total_tokens=1234.5;changed.measured_usage.sample_count=7
	check(Estimate.usage_reference(changed).contains("1235") and Estimate.usage_reference(changed).contains("24700"),"display follows content, rounds conservatively and uses actual policy cap")
	changed.measured_usage.sample_count=0;check(Estimate.usage_reference(changed).is_empty(),"missing valid samples never invent measured usage")
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	game.resident_connections.preferences.choose("codex","ultra");game.resident_connections.open("codex");game.resident_connections.tabs.current_tab=2;game.resident_connections.refresh()
	check(game.resident_connections.footer.text.contains("实测均值8993") and game.resident_connections.footer.text.contains("medium，2回合"),"resident warning uses actual complete usage samples")
	var directory:=OS.get_environment("HABITAT_POLISH_CAPTURE_DIR")
	if not directory.is_empty():DirAccess.make_dir_recursive_absolute(directory)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame
		check(game.resident_connections.get_global_rect().encloses(game.resident_connections.footer.get_global_rect()),"measured warning fits "+str(size))
		if not directory.is_empty():
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();check(image.get_size()==size,"actual warning viewport "+str(size));image.save_png(directory.path_join("usage-%dx%d.png"%[size.x,size.y]))
	game.autonomy.scheduler.config.erase("measured_usage");game.resident_connections.refresh()
	check(game.resident_connections.footer.text.contains("估算") and not game.resident_connections.footer.text.contains("实测"),"no measurement gracefully returns to honest estimate")
	check(game.links.values().all(func(link):return link._pid==-1),"display-only evidence never starts a model")
	game.queue_free();await process_frame
	print("Polish usage: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
