extends SceneTree
const Text=preload("res://scripts/localization.gd")
var game:Node
var failed:=false
var output:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func click_at(at:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true);await process_frame
func click(control:Control)->void:await click_at(control.global_position+control.size/2)
func choose(picker:OptionButton,index:int)->void:
	await click(picker)
	var popup:=picker.get_popup()
	await click_at(Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*float(popup.size.y)/picker.item_count))
func shot(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run()->void:
	output=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if output.is_empty():output=OS.get_environment("HABITAT_DATA_DIR")
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok,"showcase fixture")
	check(preload("res://scripts/save_store.gd").save_world(w,OS.get_environment("HABITAT_DATA_DIR")),"save fixture")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false
	for i in range(40):await process_frame
	game.chat.hide();game.world.director.set_all_enabled(false)
	game.view.follow_player=false;game.view.zoom=1
	# Camera-only changes, the player keeps her actual starting coordinates.
	for phase in ["day","night"]:
		# Real engine time advance to the requested phase, no direct clock assignment.
		for i in range(10000):
			if (game.world.days.phase().id=="night")== (phase=="night"):break
			game.world.advance(1)
		for id in ["home.house.01","home.house.02","home.house.03","home.house.04","home.house.05"]:
			game.view.center=game.world.point(game.world.objects[id])
			await shot(id+"-"+phase)
	game.view.center=game.world.point(game.world.objects["home.house.01"])
	await click_at(game.view.screen(game.world.point(game.world.objects["home.house.01"])))
	for i in range(10):await process_frame
	check(game.house_panel.visible,"real click opens house")
	if game.house_panel.visible:
		for locale in ["zh_CN","en"]:
			Text.select(OS.get_environment("HABITAT_DATA_DIR"),locale)
			for size in [Vector2i(960,640),Vector2i(1280,800)]:
				root.size=size
				await process_frame
				await choose(game.house_panel.appearance,1)
				check(game.world.objects["home.house.01"].get("house_appearance")=="classic","native classic choice")
				await choose(game.house_panel.appearance,0)
				check(game.world.objects["home.house.01"].get("house_appearance")=="personal","native personal choice")
				await shot("house-menu-"+locale+"-"+str(size.x))
		await click(game.house_panel.build_button)
		for i in range(5000):
			game.world.advance(.1)
			if game.world.actors.human.region_id.begins_with("room."):break
		for i in range(10):await process_frame
		check(game.world.actors.human.region_id.begins_with("room."),"real enter button routes into room")
		await shot("house-interior")
	print("HOUSE INPUT ",not failed," OUTPUT ",output)
	quit(1 if failed else 0)
