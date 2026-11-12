extends SceneTree
const World = preload("res://scripts/world_state.gd")
const IDS = ["ai-gpt", "ai-claude", "ai-gemini", "ai-grok", "ai-deepseek", "ai-glm", "ai-qwen", "ai-kimi"]
var game: Node
var output := ""
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.get_size()==Vector2i(1280,800))
	assert(image.save_png(output.path_join(name+".png"))==OK)
func select(picker: OptionButton, id: String) -> void:
	for i in range(picker.item_count):
		if str(picker.get_item_metadata(i))==id:
			picker.select(i); picker.item_selected.emit(i); return
	assert(false,"missing option "+id)
func select_text(picker: OptionButton, value: String) -> void:
	for i in range(picker.item_count):
		if picker.get_item_text(i)==value:picker.select(i);picker.item_selected.emit(i);return
	assert(false,"missing text "+value)
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	output = OS.get_environment("HABITAT_SPARE_EVIDENCE")
	if not directory.contains("youqi-test-") or output.is_empty():quit(1);return
	root.content_scale_size=Vector2i.ZERO;DisplayServer.window_set_size(Vector2i(1280,800));root.size=Vector2i(1280,800)
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	game.island_hud.open_appearance("codex");game.editor.open_art("ai-gpt")
	await process_frame; await process_frame
	game.editor.work_picker.show_popup();await shot("01-workshop-spares")
	game.editor.work_picker.get_popup().hide()
	select_text(game.editor.group_picker,"劳动");select_text(game.editor.action_picker,"砍树");select_text(game.editor.direction_picker,"正面")
	game.editor.frame_picker.show_popup();await shot("04-reused-frame-label")
	game.editor.frame_picker.get_popup().hide()
	select(game.editor.resident_picker,"codex");game.editor._assign_appearance();game.editor.close_workshop()
	var plaza:Array=game.world.map_anchor("plaza.center")
	game.world.actors.codex.position=[float(plaza[0]),float(plaza[1])+5.0]
	var p:Vector2=game.world.point(game.world.actors.codex);var accepted:=false
	for delta in [Vector2(5,0),Vector2(-5,0),Vector2(0,5),Vector2(0,-5)]:
		var target:Vector2=p+delta
		if game.world.walkable("home",target) and game.world.command("codex",{"intent":"move","x":target.x,"y":target.y}).ok:
			accepted=true;break
	assert(accepted)
	game.world.advance(.1);game.view.show_region("home");game.view.center=game.world.point(game.world.actors.codex);game.view.zoom=1;game.view.follow_player=false;game.view.queue_redraw()
	await shot("02-selected-resident-walking")
	game.world.command("codex",{"intent":"stop"})
	var actors:Array=game.world.actors.keys()
	while actors.size()<8:
		var id:="spare-shot-"+str(actors.size());assert(game.world.add_companion(id,"研究参照"));actors.append(id)
	var center:Array=game.world.map_anchor("plaza.center")
	for index in range(8):
		var actor:Dictionary=game.world.actors[actors[index]]
		actor.appearance_id=IDS[index];actor.position=[float(center[0])+float(index-3.5)*2.7,float(center[1])+5];actor.activity="idle";actor.facing="down"
	game.view.center=Vector2(center[0],center[1]+4);game.view.zoom=1;game.view.motion.advance(.1,game.world.actors);game.view.queue_redraw()
	for child in game.get_children():
		if child is CanvasLayer:child.hide()
	await shot("03-eight-appearances")
	print("Four actual Godot viewports; temporary world only.");quit()
