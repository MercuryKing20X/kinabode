extends SceneTree
const World=preload("res://scripts/world_state.gd")
const F=preload("res://tests/standard_fixture.gd")
var game:Node
var f:RefCounted
var output:String
func _initialize()->void:call_deferred("run")
func pair(name:String)->void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(size);root.size=size;root.content_scale_size=Vector2i.ZERO
		game.island_hud.refresh();game.view.queue_redraw()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var im:=root.get_texture().get_image();assert(im.get_size()==size);assert(im.save_png(output.path_join(name+"-%sx%s.png"%[size.x,size.y]))==OK)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","standard");output=OS.get_environment("HABITAT_STANDARD_EVIDENCE")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
	f=F.new();f.w=game.world;game.view.follow_player=false;game.view.zoom=1;await process_frame
	game.view.center=f.w.point(f.w.actors.human)+Vector2(3,-1);game.view.hover_id="";await pair("01-first-look")
	game.view.center=f.w.standard.board_point("home.barbecue")+Vector2(7,-2);await pair("02-plaza-distant")
	var at:Vector2=f.w.standard.board_point("home.barbecue")
	assert(f.job({"intent":"move","x":at.x+4,"y":at.y+2}));game.view.hover_id="";game.view.center=at+Vector2(7,-2);await pair("03-plaza-near")
	game.island_hud.context_signature="";await pair("04-wardrobe-rows")
	game._show_opening_board();await pair("05-notice-board")
	var dialog:AcceptDialog=game.get_children().filter(func(n):return n is AcceptDialog and n.title.begins_with("告示板"))[0]
	var body:VBoxContainer=dialog.get_children().filter(func(n):return n is VBoxContainer)[0]
	var row:HBoxContainer=body.get_children().filter(func(n):return n is HBoxContainer)[0]
	var where:Button=row.get_children().filter(func(n):return n is Button)[0];where.pressed.emit();await pair("06-where-highlight")
	print("Standard polish: 12 actual viewport screenshots complete")
	game.queue_free();await process_frame;await create_timer(.3).timeout;quit()
