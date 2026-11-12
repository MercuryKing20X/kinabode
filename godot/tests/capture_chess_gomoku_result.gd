extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Text=preload("res://scripts/localization.gd")
var game: Node
func _initialize() -> void: call_deferred("run")
func mouse(at: Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
func find_button(node: Node,label: String) -> BaseButton:
	if node is BaseButton and node.text==label:return node
	for child in node.get_children():
		var found:=find_button(child,label)
		if found!=null:return found
	return null
func click_label(node: Node,key: String) -> void:
	var button:=find_button(node,Text.text(key));assert(button!=null,"missing "+key)
	await UI.click(self,button)
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_PLAYTEST_CAPTURE").path_join(name+".png"))
func step(delta: float) -> void:
	game._process(delta);game.view._process(delta)
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	assert(directory.contains("youqi-test-") and not OS.get_environment("HABITAT_PLAYTEST_CAPTURE").is_empty())
	var locale:=OS.get_environment("CHESS_LOCALE")
	Text.select(directory,locale)
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	assert(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok)
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point: Vector2=fixture.point(fixture.leisure.sites["play.gomoku"])
	fixture.actors.human.position=[point.x,point.y+2]
	assert(fixture.gomoku.begin_host("play.gomoku","companion-2",true,"local","easy").get("ok",false))
	var session: Dictionary=fixture.gomoku.sessions["play.gomoku"]
	fixture.gomoku.pause(session,"fixture")
	var history: Array=[[3,7],[0,0],[4,7],[0,2],[5,7],[0,4],[6,7],[1,0]]
	assert(preload("res://scripts/gomoku_rules.gd").replay(history).get("winner",-1)==0)
	session.history=history;session.revision+=history.size()
	assert(fixture.gomoku.valid_saved(fixture.gomoku.saved(),fixture.actors,fixture.leisure.sites))
	assert(preload("res://scripts/save_store.gd").save_world(fixture,directory))
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await UI.click(self,game.island_hud.chess_button)
	assert(game.chess_choice.visible)
	await click_label(game.chess_choice,"ui.main.gomoku")
	var panel: Control=game.gomoku_panel
	await UI.click(self,panel.resume_button)
	for tick in range(6000):
		step(0.1)
		if game.world.gomoku.sessions.get("play.gomoku",{}).get("phase","")=="playing":break
	assert(game.world.gomoku.sessions["play.gomoku"].phase=="playing")
	for i in range(10):step(0.1);await process_frame
	var geom: Dictionary=panel.board.geometry()
	await mouse(panel.board.global_position+geom.origin+Vector2(7,7)*float(geom.step))
	step(0.1);await process_frame
	var terminal: Dictionary=game.world.gomoku.sessions["play.gomoku"]
	assert(terminal.get("result","")=="five" and terminal.get("winner_id","")=="human")
	await capture("gomoku-final-"+locale+"-terminal")
	step(0.55);await process_frame;await capture("gomoku-final-"+locale+"-stamp")
	step(0.7);await process_frame;await capture("gomoku-final-"+locale+"-confetti")
	await mouse(panel.presentation.left.global_position+Vector2(4,panel.presentation.left.size.y-10))
	assert(not panel.presentation.result_layer.visible and panel.card.visible)
	await UI.click(self,panel.presentation.reopen)
	assert(panel.presentation.result_layer.visible)
	await mouse(panel.presentation.left.global_position+Vector2(4,panel.presentation.left.size.y-10))
	assert(not panel.presentation.result_layer.visible and panel.card.visible)
	for i in range(40):step(0.1);await process_frame
	await capture("gomoku-final-"+locale+"-line")
	print("PASS gomoku result ",locale," history=",terminal.history.size()," line=",panel.presentation.speech.text)
	quit(0)
