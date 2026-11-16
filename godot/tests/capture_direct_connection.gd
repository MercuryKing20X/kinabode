extends SceneTree
class Stub extends "res://scripts/companion_link.gd":
	func probe_connection()->bool:return false
	func shutdown()->void:pass
func _initialize()->void:run.call_deferred()
func run()->void:
	var base:=OS.get_environment("HABITAT_DATA_DIR")
	root.size=Vector2i(1280,800)
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,base)
	pool.factory=func(_id):return Stub.new()
	pool.settings.set_value("selection","codex","openai");pool.settings.set_value("api","codex","openai");pool.settings.set_value("openai","base","http://127.0.0.1:11434/v1");pool.settings.set_value("openai","chat","your-installed-model");pool.settings.set_value("openai","thinking","your-installed-model");pool.persist()
	var panel:=preload("res://scripts/connection_overview.gd").new();root.add_child(panel)
	var theme_data:=Theme.new();theme_data.default_font=preload("res://assets/fonts/NotoSansSC.ttf");panel.theme=theme_data
	panel.setup(base);panel.open()
	for locale in ["zh_CN","en"]:
		TranslationServer.set_locale(locale);panel.refresh()
		for page in ["settings","residents"]:
			var scroll:ScrollContainer=panel.get_child(0);scroll.scroll_vertical=0 if page=="settings" else 320
			await process_frame;await process_frame;await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(base.path_join("connection-"+locale+"-"+page+".png"))
	panel.queue_free();await process_frame;quit()
