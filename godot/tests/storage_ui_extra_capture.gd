extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const Audit=preload("res://tests/visible_locale_audit.gd")
# Called only after the caller's genuine input has opened this panel.
static func capture(tree:SceneTree,game:Node,panel:Node,prefix:String)->Array:
	var problems:Array=[]
	var output:String=OS.get_environment("HABITAT_UI_EXTRA_CAPTURE")
	if output.is_empty():return problems
	DirAccess.make_dir_recursive_absolute(output)
	var original_size:Vector2i=tree.root.size
	var original_locale:String=TranslationServer.get_locale()
	for extent in [Vector2i(1280,800),Vector2i(960,640)]:
		tree.root.size=extent;DisplayServer.window_set_size(extent)
		await tree.process_frame;await tree.process_frame
		for locale in ["zh_CN","en"]:
			TranslationServer.set_locale(locale);LocalText.events.changed.emit()
			await tree.process_frame;await tree.process_frame
			problems.append_array(Audit.violations(panel,locale))
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				tree.root.get_texture().get_image().save_png(output.path_join(prefix+"-"+locale+"-%dx%d.png"%[extent.x,extent.y]))
	TranslationServer.set_locale(original_locale);LocalText.events.changed.emit()
	tree.root.size=original_size;DisplayServer.window_set_size(original_size)
	await tree.process_frame;await tree.process_frame
	return problems
