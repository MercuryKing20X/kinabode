extends SceneTree
const Rules=preload("res://scripts/gomoku_rules.gd")
class FakeAdapter extends "res://scripts/companion_link.gd":
	var sent: Array=[]
	func _start() -> bool:return true
	func _send(message: Dictionary) -> bool:sent.append(message.duplicate(true));return true
var game: Node
var checks:=0
var failed:=false
var output:=""
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func step(delta: float=.1) -> void:game._process(delta);game.view._process(delta)
func job(id: String,args: Dictionary) -> bool:
	if not game.world.command(id,args).ok:return false
	for i in range(18000):
		game.world.advance(.1)
		if not game.world.work.jobs.has(id) and not game.world._routes.has(id):return true
	return false
func shot(name: String) -> void:
	game.gomoku_panel.refresh()
	if output.is_empty():return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var bounds:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	var panel: Control=game.gomoku_panel
	if panel.card.visible:
		check(bounds.encloses(panel.card.get_global_rect()),"chess card fits "+name)
		check(panel.card.get_global_rect().encloses(panel.board.get_global_rect()),"full board inside card "+name)
		check(panel.presentation.left.get_global_rect().encloses(panel.presentation.portrait.get_global_rect()) and not panel.presentation.left.get_global_rect().intersects(panel.board.get_global_rect()) and not panel.presentation.right.get_global_rect().intersects(panel.board.get_global_rect()),"opponent in left column and board clear of both side columns "+name)
		check(panel.board.size.y>230,"board remains clickable in "+name)
	if panel.reopen_button.visible:check(bounds.encloses(panel.reopen_button.get_global_rect()),"chess reentry fits "+name)
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_GOMOKU_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	for link in game.links.values():link.queue_free()
	game.links.clear();game.dialogue_adapter_factory=func(_id,_scope):return FakeAdapter.new()
	game._ensure_link("codex");game.link=game.links.codex
	var world: RefCounted=game.world
	world.hunger.enabled=false # Non-hungry chess contract; hunger pause has its own probe.
	var positions: Dictionary=world.actors.duplicate(true)
	game._open_gomoku()
	check(world.actors==positions and world.work.jobs.is_empty(),"opening chess never moves or seats a resident")
	check(game.gomoku_panel.build_button.visible and not game.gomoku_panel.start_button.visible,"unfinished corner offers real construction")
	await shot("foundation")
	check(job("codex",{"intent":"gather_wood","tree_count":10}) and job("codex",{"intent":"build_facility","target_id":"play.gomoku"}),"QA constructs actual table from actual wood")
	game.view.center=world.point(world.leisure.sites["play.gomoku"])+Vector2(0,1);game.view.zoom=1.1
	game.gomoku_panel.card.hide();await shot("table-built")
	game.gomoku_panel.open();game.gomoku_panel.start_button.pressed.emit()
	check(world.gomoku.sessions.has("play.gomoku"),"explicit self-seat button creates match")
	for i in range(1500):
		step()
		if world.gomoku.sessions["play.gomoku"].phase!="arriving":break
	var match_state: Dictionary=world.gomoku.sessions["play.gomoku"]
	check(match_state.phase=="playing","player and invited partner physically arrive")
	world.director.routines.codex.set_enabled(true)
	for tick in range(30):step(.5)
	game.gomoku_panel.preset_menu.get_popup().id_pressed.emit(0);step(0)
	await shot("board-open")
	await shot("companion-1280x800")
	root.size=Vector2i(960,640);await shot("companion-960x640");root.size=Vector2i(1280,800)
	var panel: Control=game.gomoku_panel
	panel.refresh()
	var geometry: Dictionary=panel.board.geometry()
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=geometry.origin+Vector2(7,7)*float(geometry.step)
	panel.board._gui_input(click)
	check(match_state.history==[[7,7]],"actual board hit submits exactly selected intersection")
	panel.board._gui_input(click)
	check(match_state.history.size()==1,"double-click cannot place second human stone")
	for i in range(25):step()
	check(match_state.history.size()==2,"unconnected local partner returns one legal move")
	await shot("two-moves")
	panel.card.hide();panel.refresh();await shot("seated-world")
	check(not panel.portraits.is_visible_in_tree(),"portraits hide with collapsed chess card")
	check(panel.reopen_button.visible and match_state.phase=="playing","close leaves game active with reentry")
	panel.reopen_button.pressed.emit();panel.pause_button.pressed.emit()
	check(match_state.phase=="paused" and world.work.jobs.is_empty(),"pause releases both seats and preserves board")
	await shot("paused")
	panel.resume_button.pressed.emit()
	for i in range(1500):
		step()
		if match_state.phase!="arriving":break
	check(match_state.phase=="playing" and match_state.history.size()==2,"explicit resume preserves exact moves")
	root.size=Vector2i(960,640);await shot("small-board")
	panel.card.hide();await shot("small-reentry");panel.card.show()
	root.size=Vector2i(1280,800)
	for turn in range(225):
		if match_state.phase=="finished":break
		if world.gomoku._turn(match_state)=="human":
			var state:=Rules.replay(match_state.history);var p:=Rules.choose(state.board,1+match_state.history.size()%2,"normal",world.gomoku.config,world.gomoku.rng)
			panel.refresh();panel.submit("gomoku_move",{"x":p.x,"y":p.y})
		for i in range(22):step()
		if turn==5:await shot("midgame")
	check(match_state.phase=="finished" and world.gomoku.memories.size()==1,"UI game reaches actual result and memory")
	await shot("finished")
	check(panel.start_button.visible and not panel.resign_button.visible,"result offers explicit rematch")
	# True model mode with a fake provider: no production inference.
	panel.mode.select(1);panel.color.select(1);panel.start_button.pressed.emit()
	match_state=world.gomoku.sessions["play.gomoku"]
	for i in range(1500):
		step()
		if match_state.phase!="arriving":break
	for i in range(40):step()
	panel.refresh()
	check(match_state.phase=="playing" and match_state.history.is_empty() and panel.model_button.visible,"model mode never substitutes a local move or auto-wakes a model")
	var connection: Node=game.links.codex
	var before: int=connection.sent.size();panel.model_button.pressed.emit()
	check(connection.sent.size()==before+1 and connection.sent.back().text.contains("只走本轮的一步"),"explicit model-step button sends exactly one game message")
	game._bound_companion_event({"kind":"action","turn_key":connection.turn_key,"id":"fake-chess-action","command":{"intent":"gomoku_move","site_id":"play.gomoku","match_id":match_state.id,"revision":match_state.revision,"x":7,"y":7}},"codex")
	check(match_state.history==[[7,7]],"actual adapter action routes into same engine rules")
	game._bound_companion_event({"kind":"question","id":"fake-chess-question","text":"测试用提问：先歇一会儿吗？","choices":["歇一会"]},"codex")
	check(match_state.phase=="paused" and world.work.claims.is_empty(),"exact model question pauses chess and releases seats")
	check(not panel.card.visible and game.chat.visible,"question gets visible dialogue priority over the board")
	await shot("question-priority")
	panel.open();await shot("question-paused")
	game._cancel_resident_turn("codex");game.chat.hide();game.chat_input.release_focus();panel.resume_button.pressed.emit()
	for i in range(1500):
		step()
		if match_state.phase!="arriving":break
	for index in range(4):
		panel.refresh();panel.submit("gomoku_move",{"x":1+index*2,"y":1})
		game._bound_companion_event({"kind":"action","id":"test-model-stone-%s"%index,"command":{"intent":"gomoku_move","site_id":"play.gomoku","match_id":match_state.id,"revision":match_state.revision,"x":7,"y":8+index}},"codex")
	check(match_state.phase=="finished" and match_state.result=="five" and match_state.winner_id=="codex","legal bound-client moves produce actual five-stone terminal result")
	panel.open();await shot("finished-five")
	check(game.links.values().all(func(link):return link._pid==-1),"no real model process was started")
	game.queue_free();await process_frame
	print("Gomoku controller: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
