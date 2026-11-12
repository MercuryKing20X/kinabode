extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
class Fake extends "res://scripts/companion_link.gd":
	var sent: Array=[]
	func _start() -> bool:return true
	func _send(message: Dictionary) -> bool:sent.append(message.duplicate(true));return true
var game: Node
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func step(seconds: float) -> void:
	for i in range(int(ceil(seconds/.5))):game._process(.5)
func calls(link: Node) -> int:return link.sent.filter(func(message):return message.kind=="chat").size()
func action(link: Node,g: Dictionary,x: int,y: int,speech: String="") -> void:
	link._accept_event({"kind":"action","id":"act-"+str(checks),"turn_key":link.turn_key,"command":{"intent":"gomoku_move","site_id":g.site_id,"match_id":g.id,"revision":g.revision,"x":x,"y":y,"speech":speech}})
func ready(link: Node) -> void:link._accept_event({"kind":"state","state":"ready","turn_key":link.turn_key,"turnComplete":true})
func shots(name: String) -> void:
	var output:=OS.get_environment("HABITAT_GOMOKU_DIALOGUE_CAPTURE")
	if output.is_empty():return
	DirAccess.make_dir_recursive_absolute(output)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.gomoku_panel.refresh();await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name+"-%dx%d.png"%[size.x,size.y]))
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);await process_frame
	game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus();game.world.director.set_all_enabled(false)
	for link in game.links.values():link.queue_free()
	game.links.clear();game.dialogue_adapter_factory=func(_id,_scope):return Fake.new();
	game._ensure_link("codex")
	var link: Node=game.links.codex;var w: RefCounted=game.world
	w.hunger.enabled=false # Isolate dialogue barriers from the hungry-chess exception.
	check(F.job(w,"codex",{"intent":"gather_wood","tree_count":10}) and F.job(w,"codex",{"intent":"build_facility","target_id":"play.gomoku"}),"real wood and actual table")
	game._open_gomoku();game._begin_gomoku("play.gomoku","codex",false,"model","normal");step(100)
	var g: Dictionary=w.gomoku.sessions["play.gomoku"]
	check(g.phase=="playing" and g.history.is_empty(),"model board waits with no hidden local move")
	check(game.gomoku_dialogue.request("codex",g.site_id) and calls(link)==1,"one explicit step opens exactly one existing private model round")
	action(link,g,15,0,"我已经走好啦")
	check(g.history.is_empty() and w.gomoku.companion.bubble(g,"codex").is_empty(),"illegal move does not show its attached speech as completed")
	action(link,g,7,7,"我先落在这里。")
	check(g.history==[[7,7]] and w.gomoku.companion.bubble(g,"codex").source=="model","accepted move and attached line share one real commit")
	check(game.view.speech_by_actor.codex.text=="我先落在这里。","same actual line synchronizes to table-side bubble")
	await shots("model-move")
	action(link,g,8,8,"再下一步")
	check(g.history.size()==1,"same round cannot sneak in a second move")
	ready(link)
	check(game.gomoku_dialogue.chat(g.site_id,"这步真有意思") and calls(link)==2,"board typing reuses the original direct channel")
	var old_key: String=link.turn_key;var before: int=g.history.size()
	action(link,g,8,8,"偷偷下一步")
	check(g.history.size()==before,"board chat round cannot place a stone")
	link._accept_event({"kind":"assistant","turn_key":old_key,"text":"我在看这条斜线，你慢慢想。"})
	check(w.gomoku.companion.bubble(g,"codex").text=="我在看这条斜线，你慢慢想。","plain chat reply shows alongside portrait")
	await shots("model-chat")
	check(game.dialogue.histories["direct:codex"].any(func(entry):return entry.text=="我在看这条斜线，你慢慢想。"),"same reply stays in original private history")
	link.cancel_turn()
	game._bound_companion_event({"kind":"assistant","turn_key":old_key,"text":"迟到的旧话"},"codex")
	game._bound_companion_event({"kind":"action","id":"late","turn_key":old_key,"command":{"intent":"gomoku_move","site_id":g.site_id,"match_id":g.id,"revision":g.revision,"x":6,"y":6}},"codex")
	check(g.history.size()==before and w.gomoku.companion.bubble(g,"codex").text!="迟到的旧话","cancel generation rejects late text and action")
	step(60);check(g.history.size()==before and calls(link)==2,"chat and replies never open extra turns or advance board")
	check(game.links.values().all(func(connection):return connection._pid==-1),"fake adapters only, zero provider process")
	for player in game.view.sounds.values():player.stop()
	game.queue_free();await process_frame;await create_timer(.1).timeout
	print("Gomoku dialogue: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
