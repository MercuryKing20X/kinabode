extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const L=preload("res://scripts/localization.gd")
const Audit=preload("res://tests/visible_locale_audit.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR");assert(data.contains("youqi-"))
	var output:=OS.get_environment("HABITAT_LOCALE_CAPTURE");assert(not output.is_empty());DirAccess.make_dir_recursive_absolute(output)
	var game:Node=UI.init_game(self)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;DisplayServer.window_set_size(size);await process_frame;await process_frame
		for locale in ["zh_CN","en"]:
			L.ensure();TranslationServer.set_locale(locale);L.events.changed.emit();await process_frame;await process_frame
			var entries:Array=UI.descendants(game).filter(func(n):return n is Button and n.is_visible_in_tree() and n.text.begins_with(L.text("storage.title")))
			if entries.is_empty() or not await UI.click(self,entries[0]):failures+=1;continue
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("storage-"+locale+"-%dx%d.png"%[size.x,size.y]))
			failures+=Audit.violations(game.storage_panel,locale).size()
			await UI.click(self,game.storage_panel.close_button)
	print("Storage GPU capture failures=",failures);quit(1 if failures else 0)
