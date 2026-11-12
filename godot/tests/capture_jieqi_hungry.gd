extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Text=preload("res://scripts/localization.gd")
var game: Node
func _initialize() -> void:call_deferred("run")
func mouse(at: Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var world:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");world.residents.provision(world);world.library=preload("res://scripts/character_library.gd").new();world.library.configure(directory);assert(preload("res://scripts/world_opening.gd").apply(world,world.library,"showcase").ok);world.intelligence.activate_presets();world.hunger.start()
	# Fixture advances actual hunger time before save; never edits thresholds or quantity.
	for tick in range(170):world.advance(10)
	assert(preload("res://scripts/save_store.gd").save_world(world,directory))
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=world;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	for frame_index in range(20):await process_frame
	game.view.center=world.point(world.leisure.sites["play.gomoku"]);game.view.zoom=1
	await mouse(game.view.screen(world.point(world.leisure.sites["play.gomoku"])))
	await mouse(Vector2(game.chess_choice.position)+Vector2(game.chess_choice.size)*Vector2(0.5,0.75))
	for frame_index in range(10):await process_frame
	var panel: Control=game.jieqi_panel
	var start: Button=panel.card.get_child(0).get_child(0).get_child(1)
	var clicked:=await UI.click(self,start)
	var ok: bool=clicked and panel.info.text==Text.text("jieqi.hungry")
	print("Jieqi hungry rejection: ",ok," rank=",world.hunger.rank("codex")," text=",panel.info.text)
	var out:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not out.is_empty():await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(out.path_join("jieqi-hungry-refusal.png"))
	quit(0 if ok else 1)
