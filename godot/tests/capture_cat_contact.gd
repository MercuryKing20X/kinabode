extends SceneTree
const Text=preload("res://scripts/localization.gd")
var game:Node
var failed:=false
var output:String
func _initialize()->void:call_deferred("run")
func click_at(at:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true);await process_frame
func find_cat_ui()->Node:
	for child in game.get_children():
		if child.get_script()==preload("res://scripts/cat_companion_ui.gd"):return child
	return null
func find_button(node:Node,text:String)->Button:
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var b:=find_button(child,text)
		if b!=null:return b
	return null
func check(value:bool,label:String)->void:
	if not value:failed=true;push_error(label)
func run()->void:
	output=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if output.is_empty():output=OS.get_environment("HABITAT_DATA_DIR")
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok,"showcase fixture")
	check(preload("res://scripts/save_store.gd").save_world(w,OS.get_environment("HABITAT_DATA_DIR")),"save cat fixture")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false
	for i in range(40):await process_frame
	game.chat.hide();game.world.director.set_all_enabled(false)
	game.view.follow_player=true;game.world.cat.next_decision=10000
	var ui:Node=find_cat_ui();check(ui!=null,"cat UI connected")
	for locale in ["zh_CN","en"]:
		Text.select(OS.get_environment("HABITAT_DATA_DIR"),locale)
		for size_value in [Vector2i(960,640),Vector2i(1280,800)]:
			root.size=size_value
			for i in range(5):await process_frame
			await click_at(game.view.screen(game.world.cat.position)-Vector2(0,16)*game.view.zoom)
			for i in range(3):await process_frame
			check(is_instance_valid(ui.menu) and ui.menu.visible,"native cat click menu")
			if not is_instance_valid(ui.menu):continue
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("cat-menu-"+locale+"-"+str(size_value.x)+".png"))
			var hold:=find_button(ui.menu,Text.text("cat.hold"))
			await click_at(Vector2(ui.menu.position)+hold.global_position+hold.size/2)
			check(game.world.cat.carrier=="human","native hold")
			await click_at(game.view.screen(game.world.cat.position)-Vector2(0,16)*game.view.zoom)
			for i in range(3):await process_frame
			if is_instance_valid(ui.menu):
				var pet:=find_button(ui.menu,Text.text("cat.pet"))
				await click_at(Vector2(ui.menu.position)+pet.global_position+pet.size/2)
				check(game.world.cat.carrier.is_empty() and game.world.cat.pose=="pet","native pet")
	print("CAT INPUT ",not failed," OUTPUT ",output)
	quit(1 if failed else 0)
