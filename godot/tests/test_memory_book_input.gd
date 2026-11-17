extends SceneTree
class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return true
	func _send(_message:Dictionary)->bool:return true
const UI=preload("res://tests/barbecue_ui_fixture.gd")
func _initialize()->void:call_deferred("run")
func shot(name:String)->void:
	await process_frame;RenderingServer.force_draw(false);root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join(name+".png"))
func run()->void:
	node_added.connect(func(node):
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":node.dialogue_adapter_factory=func(_id,_scope):return Fake.new())
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"));root.size=Vector2i(1280,800)
	var books:=preload("res://scripts/memory_books.gd").new();assert(books.setup(dir));books.remember_chat("companion-2","old-world","quote","我喜欢下雨",1)
	books.remember_chat("companion-2","old-world","quote-two","我喜欢海风",1)
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title
	for i in 20:await process_frame
	assert(await UI.click(self,title.menu.get_node("memory")));assert(title.book_panel.visible)
	await shot("memory-days")
	var panel:Node=title.book_panel
	for index in range(1,4):
		assert(await UI.click(self,panel.tabs))
		var popup:PopupMenu=panel.tabs.get_popup()
		for key in [KEY_HOME]+Array(range(index)).map(func(_i):return KEY_DOWN)+[KEY_ENTER]:
			for pressed in [true,false]:
				var e:=InputEventKey.new();e.keycode=key;e.pressed=pressed;popup.push_input(e,true);await process_frame
		await shot("memory-tab-"+str(index))
	assert(books.export_html(dir.path_join("album.html"),false))
	var close_buttons:Array=UI.descendants(panel).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("memory.close"))
	assert(await UI.click(self,close_buttons[0]));assert(await UI.click(self,title.menu.get_node("new")))
	await create_timer(.35).timeout
	var deadline:int=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline and (not is_instance_valid(current_scene) or current_scene.get_script()!=load("res://scripts/main.gd")):await process_frame
	var game:Node=current_scene;assert(game.get("memory_books")!=null);assert(game.memory_books.list_for("companion-2").size()>=3)
	game.set_process(false)
	var heard:=false
	for i in 2000:
		game._process(.1)
		if game.view.speech_by_actor.get("companion-2",{}).get("text","").contains("又见面"):
			heard=true;break
	assert(heard);await shot("reunion")
	print("MEMORY_UI_PASS four tabs/new world persistence/reunion/HTML")
	game.queue_free();await process_frame;quit()
