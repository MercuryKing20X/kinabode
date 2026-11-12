extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Fake=preload("res://tests/test_gomoku_match_host.gd").Fake
var game: Node
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func step(seconds: float) -> void:
	for tick in range(int(ceil(seconds/.2))):game._process(.2)
func shot(name: String) -> void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.gomoku_panel.refresh();await process_frame;await process_frame
		var p: Control=game.gomoku_panel
		if not output.is_empty():print("PORTRAIT_TRANSFORMS ",size," logical=",p.size," rect=",p.get_viewport_rect().size," texture=",root.get_texture().get_size()," global=",p.portraits.get_global_transform().get_scale()," canvas=",p.portraits.get_global_transform_with_canvas().get_scale()," final=",root.get_final_transform().get_scale())
		check(root.get_visible_rect().encloses(p.card.get_global_rect()) and p.card.get_global_rect().encloses(p.board.get_global_rect()),"original board and buttons remain in actual viewport "+str(size))
		check(p.presentation.portrait.is_visible_in_tree() and p.presentation.left.get_global_rect().encloses(p.presentation.portrait.get_global_rect()) and not p.presentation.left.get_global_rect().intersects(p.board.get_global_rect()) and not p.presentation.right.get_global_rect().intersects(p.board.get_global_rect()),"current opponent in left column; both side columns clear of board "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join(name+"-%dx%d.png"%[size.x,size.y]))
func play(g: Dictionary,x: int,y: int) -> void:
	var id: String=game.world.gomoku._turn(g);var link: Node=game.links[id];var key: String=link.turn_key
	link._accept_event({"kind":"action","turn_key":key,"id":"ui-move-"+str(checks),"command":{"intent":"gomoku_move","site_id":g.site_id,"match_id":g.id,"revision":g.revision,"x":x,"y":y,"speech":"我把棋子落在这里。"}})
	link._accept_event({"kind":"usage","turn_key":key,"total_tokens":100,"input_tokens":80,"output_tokens":20,"complete":true})
	link._accept_event({"kind":"state","turn_key":key,"state":"ready","turnComplete":true});step(.2)
func run() -> void:
	var data_dir:=OS.get_environment("HABITAT_DATA_DIR")
	if not data_dir.contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_GOMOKU_AI_CAPTURE")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);await process_frame
	game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus();game.world.director.set_all_enabled(false)
	for link in game.links.values():link.queue_free()
	game.links.clear();game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	for id in ["codex","companion-2"]:
		game._ensure_link(id);game.resident_connections.preferences.choose(id,"ultra");game.links[id]._accept_event({"kind":"state","state":"ready"})
	var w: RefCounted=game.world;var human: Dictionary=w.actors.human.duplicate(true)
	w.hunger.enabled=false # Isolate the match UI and budget contract.
	check(F.job(w,"codex",{"intent":"gather_wood","tree_count":10}) and F.job(w,"codex",{"intent":"build_facility","target_id":"play.gomoku"}),"viewport table built from real wood")
	game._open_gomoku();var panel: Control=game.gomoku_panel;panel.game_type.select(1);panel.black_source.select(2);panel.white_source.select(2);panel.refresh()
	panel.ai_button.pressed.emit()
	check(panel.confirm.visible and w.work.jobs.is_empty() and not w.gomoku.sessions.has("play.gomoku"),"choosing players cannot move anyone before explicit budget confirmation")
	panel.confirm.confirmed.emit();panel.confirm.hide()
	check(w.gomoku.sessions.has("play.gomoku"),"actual host confirmation creates AI match")
	if not w.gomoku.sessions.has("play.gomoku"):quit(1);return
	var g: Dictionary=w.gomoku.sessions["play.gomoku"]
	for tick in range(2000):
		step(.2)
		if g.phase!="arriving":break
	check(g.phase=="playing" and game.gomoku_match_host.pending.has("codex"),"real arrival starts one fake model step")
	await shot("ai-double-think")
	play(g,7,7);await shot("ai-double-move")
	play(g,1,1);play(g,6,7);play(g,2,1);play(g,8,7);step(2)
	check(w.gomoku.companion.facts(g).open_three,"actual accepted history forms open-three threat")
	await shot("ai-advantage")
	var context_path:=OS.get_environment("HABITAT_GOMOKU_CONTEXT_OUTPUT")
	if not context_path.is_empty():
		var file:=FileAccess.open(context_path,FileAccess.WRITE);file.store_string(JSON.stringify(game.gomoku_match_host.context("codex",g),"  "));file.close()
	var id: String=w.gomoku._turn(g);var key: String=game.links[id].turn_key
	game.links[id]._accept_event({"kind":"usage","turn_key":key,"total_tokens":120100,"input_tokens":120080,"output_tokens":20,"complete":true})
	check(g.phase=="paused" and g.reason.contains("预算"),"actual fake usage report triggers visible budget pause")
	await shot("ai-paused-budget")
	check(w.actors.human==human and game.links.values().all(func(link):return link._pid==-1),"spectator unchanged and fake adapters only")
	panel.card.hide();check(not panel.portraits.is_visible_in_tree(),"dual portraits collapse together")
	for player in game.view.sounds.values():player.stop()
	game.queue_free();await process_frame;await create_timer(.1).timeout
	print("Gomoku AI controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
