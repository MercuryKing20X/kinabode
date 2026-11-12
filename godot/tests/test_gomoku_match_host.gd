extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
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
	for tick in range(int(ceil(seconds/.2))):game._process(.2)
func count(id: String) -> int:return game.links[id].sent.filter(func(message):return message.kind=="autonomy_event").size()
func fresh(black_source: String="model",white_source: String="model") -> Dictionary:
	var w: RefCounted=game.world
	game.chat.hide();game.chat_input.release_focus() # Each fresh match starts after the preceding chat UI is closed.
	if w.gomoku.sessions.has("play.gomoku") and w.gomoku.sessions["play.gomoku"].phase not in ["finished","abandoned"]:game.gomoku_match_host.end("play.gomoku")
	for id in ["codex","companion-2"]:
		game.links[id]._accept_event({"kind":"state","state":"ready"})
	step(.2) # Apply the real frame after cancellation/answer before taking new seat claims.
	var result: Dictionary=game.gomoku_match_host.begin("play.gomoku","codex","companion-2",{"codex":black_source,"companion-2":white_source})
	check(result.ok,"explicit host starts chosen connected AI players")
	if not result.ok:return {}
	var g: Dictionary=w.gomoku.sessions["play.gomoku"]
	for tick in range(2000):
		step(.2)
		if g.phase!="arriving":break
	return g
func usage(id: String,key: String,total: int=100) -> void:game.links[id]._accept_event({"kind":"usage","turn_key":key,"input_tokens":total-20,"output_tokens":20,"total_tokens":total,"complete":true})
func move(id: String,g: Dictionary,p: Vector2i,speech: String="") -> void:
	game.links[id]._accept_event({"kind":"action","turn_key":game.links[id].turn_key,"id":"action-"+str(checks),"command":{"intent":"gomoku_move","site_id":g.site_id,"match_id":g.id,"revision":g.revision,"x":p.x,"y":p.y,"speech":speech}})
func ready(id: String,key: String) -> void:game.links[id]._accept_event({"kind":"state","turn_key":key,"state":"ready","turnComplete":true})
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);await process_frame
	game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus();game.world.director.set_all_enabled(false)
	for link in game.links.values():link.queue_free()
	game.links.clear();game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	for id in ["codex","companion-2"]:
		game._ensure_link(id);game.resident_connections.preferences.choose(id,"ultra");game.links[id]._accept_event({"kind":"state","state":"ready"})
	var w: RefCounted=game.world;var host: RefCounted=game.gomoku_match_host
	w.hunger.enabled=false # Isolate match turn leases/budgets from hungry-player pauses.
	check(F.job(w,"codex",{"intent":"gather_wood","tree_count":10}) and F.job(w,"codex",{"intent":"build_facility","target_id":"play.gomoku"}),"table built from real wood")
	var human: Dictionary=w.actors.human.duplicate(true)
	var g:=fresh()
	if g.is_empty():quit(1);return
	check(g.phase=="playing" and count("codex")==1 and count("companion-2")==0,"one current model step only, no opponent wake yet")
	step(1)
	check(g.phase=="playing" and g.ai.reserved_tokens==12000 and g.ai.unknown_tokens==0,"real in-flight frames preserve reservation; only reload/cancel may make it unknown")
	var key: String=game.links.codex.turn_key
	var readonly: Dictionary=host.context("codex",g);readonly.chess.history.append([0,0])
	check(g.history.is_empty() and JSON.stringify(host.context("codex",g)).to_utf8_buffer().size()<=4096,"AI context is actual read-only small board and own memories")
	game.links.codex._accept_event({"kind":"observe","turn_key":key,"id":"board-only","query":{}})
	check(game.links.codex.sent[-1].result.actions.actions.all(func(action):return action.id in ["gomoku_read","gomoku_move"]),"existing v2 discovery returns only real scoped chess actions")
	game.links.codex._accept_event({"kind":"action","turn_key":key,"id":"not-allowed","command":{"intent":"give","receiver_id":"human","item_id":"wood","quantity":1}})
	check(g.history.is_empty() and w.actors.human==human,"match lease cannot give resources or control human")
	check(w.command("codex",{"intent":"propose"}).get("error")=="chess_match_restricted","World also rejects non-chess actions from other bound adapter paths")
	move("codex",g,Vector2i(7,7),"我先占这里。")
	check(host.context("companion-2",g).match_dialogue[-1].text=="我先占这里。","next required step reads actual shared match words without an extra reply round")
	check(g.history.size()==1 and count("companion-2")==0,"accepted move does not wake another model before turn ends")
	usage("codex",key);ready("codex",key);step(.2)
	check(count("codex")==1 and count("companion-2")==1,"next player's required chess step opens exactly one round")
	var ledger: Dictionary=game.autonomy.scheduler.usage("codex")
	check(ledger.tokens==100 and ledger.calls==1 and ledger.reserved==0,"reported input/output/total charged once to daily autonomy ledger")
	check(game.autonomy.scheduler.records.read("codex").turns[-1].events==["对弈"],"active records clearly label chess")
	host.pause_site(g.site_id);var stale: String=game.links["companion-2"].sent.filter(func(m):return m.kind=="autonomy_event")[-1].turn_key
	game._bound_companion_event({"kind":"action","turn_key":stale,"id":"late-ai","command":{"intent":"gomoku_move","site_id":g.site_id,"match_id":g.id,"revision":g.revision,"x":1,"y":1}},"companion-2")
	check(g.phase=="paused" and g.history.size()==1 and w.work.jobs.is_empty() and w.work.claims.is_empty(),"pause rejects late steps and releases both exact tasks/seats")
	check(game.autonomy.scheduler.usage("companion-2").reserved>0,"unknown cancelled inference stays reserved, never free")
	g=fresh();var first: int=count("codex");key=game.links.codex.turn_key
	usage("codex",key);move("codex",g,Vector2i(99,0),"假的完成")
	step(.2)
	check(count("codex")==first+1 and g.history.is_empty(),"illegal step retries one model round without local substitute")
	key=game.links.codex.turn_key;usage("codex",key);move("codex",g,Vector2i(99,0),"又假装走完")
	step(3)
	check(g.phase=="paused" and g.history.is_empty() and count("codex")==first+1,"second illegal step pauses without loss or third retry")
	g=fresh();first=count("codex");key=game.links.codex.turn_key;usage("codex",key);ready("codex",key);step(.2)
	check(count("codex")==first+1,"a completed model round with no move retries at most once")
	key=game.links.codex.turn_key;usage("codex",key);ready("codex",key);step(.2)
	check(g.phase=="paused" and g.history.is_empty(),"second no-move completion pauses without pretending success")
	g=fresh();first=count("codex");step(float(w.gomoku.match_config.step_timeout)+1)
	check(g.phase=="paused" and g.history.is_empty() and count("codex")==first,"timeout pauses, never local fallback")
	g=fresh();host.pause_site(g.site_id)
	g.ai.token_limit=1
	check(w.gomoku.resume_host(g.site_id).ok,"explicit engine resume for tiny match budget probe")
	first=count("codex");step(30)
	check(g.phase=="paused" and count("codex")==first and g.history.is_empty(),"match token cap refuses before dispatch")
	var daily: Dictionary=host.policy("codex");var old_daily: int=daily.daily;daily.daily=game.autonomy.scheduler.usage("codex").calls
	check(not host.resume(g.site_id).ok and w.work.jobs.is_empty(),"daily call budget refuses before new seating")
	daily.daily=old_daily
	var old_tokens: int=daily.daily_tokens;var actual: Dictionary=game.autonomy.scheduler.usage("codex");daily.daily_tokens=int(actual.tokens)+int(actual.reserved)
	check(not host.resume(g.site_id).ok,"daily token budget cannot be reset by match reconfirmation")
	daily.daily_tokens=old_tokens
	g=fresh();game.questions["companion-2"]={"id":"held-probe","text":"先聊聊吗？","choices":["稍等"]};var held_moves: int=g.history.size();step(2)
	check(g.phase=="paused" and g.history.size()==held_moves and w.work.claims.is_empty(),"pending answer interrupts before World can advance another chess step")
	game.questions.erase("companion-2")
	g=fresh();game._send_direct("companion-2","想和你聊一会儿")
	check(g.phase=="paused" and w.work.jobs.is_empty() and w.work.claims.is_empty(),"player conversation to either side pauses full AI game")
	game.links["companion-2"].cancel_turn()
	check(Save.save_world(w,directory.path_join("match")),"save actual AI board")
	var loaded:=F.fresh();check(Save.load_world(loaded,directory.path_join("match")).ok,"AI match survives optional schema7 reload")
	check(loaded.gomoku.sessions[g.site_id].phase=="paused" and loaded.work.jobs.is_empty() and loaded._routes.is_empty(),"reload is paused without automatic calls/tasks/routes")
	g=fresh();step(.2);check(Save.save_world(w,directory.path_join("inflight")),"save pending model round without saving task/timer")
	var inflight:=F.fresh();check(Save.load_world(inflight,directory.path_join("inflight")).ok and inflight.gomoku.sessions[g.site_id].ai.unknown_tokens>0 and inflight.gomoku.sessions[g.site_id].ai.reserved_tokens==0,"reload converts real in-flight reservation to honest unknown usage")
	game._stop_resident("companion-2");check(g.phase=="paused" and w.work.claims.is_empty(),"stop of either selected player pauses both seats")
	g=fresh();game._select_chat("codex");game._change_controller(1);step(.2)
	check(g.phase=="paused" and w.work.jobs.is_empty() and w.work.claims.is_empty(),"source switch pauses and rejects old model control")
	check(w.actors.human==human and game.links.values().all(func(link):return link._pid==-1),"human remains untouched, no provider process")
	for player in game.view.sounds.values():player.stop()
	game.queue_free();await process_frame;await create_timer(.1).timeout
	print("Gomoku match host: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
