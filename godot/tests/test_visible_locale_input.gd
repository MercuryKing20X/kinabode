extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Audit=preload("res://tests/visible_locale_audit.gd")
const L=preload("res://scripts/localization.gd")
var failures:Array=[]
var records:Array=[]
var game:Node
var audit_size:=Vector2i.ZERO
var audit_locale:=""
func _initialize()->void:call_deferred("run")
func key(code:int)->void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event,true);await process_frame
func scan(name:String,locale:String,size:Vector2i)->void:
	await process_frame;await process_frame
	var allowed:Array=[]
	# Only explicitly marked custom values are exempted, never built-in names.
	for actor in game.world.actors.values():
		if actor.get("custom_name",false):allowed.append(str(actor.name))
	var problems:=Audit.violations(root,locale,allowed)
	failures.append_array(problems);records.append({"screen":name,"locale":locale,"size":[size.x,size.y],"violations":problems,"visible_texts":Audit.texts(root)})
	var output:=OS.get_environment("HABITAT_LOCALE_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(output);await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name+"-"+locale+"-%dx%d.png"%[size.x,size.y]))
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-"):quit(1);return
	game=UI.init_game(self);await process_frame;await process_frame
	if game==null or game.world==null or game.island_hud==null:push_error("locale fixture failed to initialize");quit(1);return
	for size in ([audit_size] if audit_size!=Vector2i.ZERO else [Vector2i(1280,800),Vector2i(960,640)]):
		root.size=size;DisplayServer.window_set_size(size);await process_frame
		for locale in ([audit_locale] if not audit_locale.is_empty() else ["zh_CN","en"]):
			L.ensure();TranslationServer.set_locale("en" if locale=="zh_CN" else "zh_CN");L.events.changed.emit();await process_frame
			TranslationServer.set_locale(locale);L.events.changed.emit();await process_frame;await process_frame
			await scan("hud",locale,size)
			var menu_buttons:Array=UI.descendants(game).filter(func(n):return n is MenuButton and n.is_visible_in_tree())
			for menu in menu_buttons:
				var count:int=menu.get_popup().item_count
				for index in count:
					# Fullscreen/restart are operational actions, not panel opening.
					if menu.get_popup().get_item_id(index) in [0,99] and menu.text==L.text("ui.main.settings"):continue
					await key(KEY_ESCAPE);await key(KEY_ESCAPE)
					await UI.click(self,menu);await scan("menu-"+str(menu.get_index()),locale,size)
					for step in range(index+1):await key(KEY_DOWN)
					await key(KEY_ENTER)
					await scan("panel-"+str(menu.get_index())+"-"+str(index),locale,size)
					var panel_buttons:Array=UI.descendants(game).filter(func(n):return n is Button and not n is MenuButton and not n is OptionButton and n.is_visible_in_tree() and not n.disabled and n.get_global_rect().size.x>0)
					for button in panel_buttons:
						if not is_instance_valid(button) or not button.is_visible_in_tree():continue
						if button.text in [L.text("ui.main.stop_me"),L.text("ui.main.my_view")]:continue
						# Do not execute archive/reset/delete operations while auditing UI.
						var destructive:=false
						for forbidden in ["archive","restart","delete","discard","重置","删除","归档"]:
							if forbidden in button.text.to_lower():destructive=true
						if destructive:continue
						await UI.click(self,button)
						await scan("context-"+str(menu.get_index())+"-"+str(index)+"-"+str(button.get_instance_id()),locale,size)
						await key(KEY_ESCAPE)
					await key(KEY_ESCAPE)
			# Plain buttons expose contextual HUD/connection/storage panels.
			for caption in ["storage.title","ui.main.actions","ui.main.chat","ui.main.follow"]:
				var matches:Array=UI.descendants(game).filter(func(n):return n is Button and not n is MenuButton and n.is_visible_in_tree() and (n.text.begins_with(L.text(caption)) if caption=="storage.title" else n.text==L.text(caption)))
				if matches.is_empty():continue
				await UI.click(self,matches[0]);await scan(caption.replace(".","-"),locale,size);await key(KEY_ESCAPE)
	var file:=FileAccess.open(directory.path_join("locale-visible-results.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"violations":failures},"\t"));file.close()
	if records.is_empty():failures.append({"error":"no_screens_reached"})
	for failure in failures:push_error(str(failure))
	print("Visible locale input screens=",records.size()," violations=",failures.size());quit(1 if not failures.is_empty() else 0)
