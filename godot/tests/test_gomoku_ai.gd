extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Q=preload("res://tests/gomoku_ai_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func run() -> void:
	var root_dir:=OS.get_environment("HABITAT_DATA_DIR")
	if not root_dir.contains("youqi-test-"):quit(1);return
	var w:=Q.built();var human: Dictionary=w.actors.human.duplicate(true)
	var source: Dictionary={"npc.mira":"local_easy","npc.nora":"local_normal"}
	check(not w.gomoku.begin_ai_host("play.gomoku","human","npc.mira",source).ok,"AI host may never select human")
	check(w.command("npc.mira",{"intent":"move","x":Places.point("p_53_0_44_0").x,"y":Places.point("p_53_0_44_0").y}).ok,"actual independently accepted route makes resident busy")
	check(not w.gomoku.begin_ai_host("play.gomoku","npc.mira","npc.nora",source).ok,"busy resident cannot be pulled into chess")
	F.wait(w,"npc.mira")
	check(w.gomoku.begin_ai_host("play.gomoku","npc.mira","npc.nora",source).ok,"explicit host authorizes two social local players")
	var g: Dictionary=w.gomoku.sessions["play.gomoku"]
	for i in range(1000):
		Q.advance(w,.2)
		if g.phase=="playing":break
	check(g.phase=="playing" and g.history.is_empty(),"two non-human players physically arrived before first move")
	check(w.work.jobs.size()==2 and w.work.jobs["npc.mira"].step=="using" and w.work.jobs["npc.nora"].step=="using","original Work jobs and exact Leisure seats are used")
	check(Save.save_world(w,root_dir.path_join("active")),"save active real AI game")
	var active_loaded:=F.fresh();check(Save.load_world(active_loaded,root_dir.path_join("active")).ok and active_loaded.gomoku.sessions[g.site_id].phase=="paused" and active_loaded.work.jobs.is_empty() and active_loaded.work.claims.is_empty(),"active AI reload pauses without tasks or claims")
	for id in source:
		var routine: RefCounted=w.director.routines[id];routine.set_enabled(true);routine.set_chatter(true)
	Q.advance(w,.4);check(g.history.is_empty(),"visible think delay prevents instant local turn")
	for tick in range(10000):
		Q.advance(w,.2)
		if g.phase=="paused" and g.reason.contains("步数"):
			check(w.gomoku.resume_ai_host("play.gomoku").ok,"explicit host reconfirms a further local-only step segment")
		elif g.phase not in ["arriving","playing"]:break
	check(g.phase=="finished" and not g.history.is_empty(),"local/local actual game finishes without inference")
	check(w.director.events.any(func(event):return event.context.begins_with("gomoku_") and event.source=="local_rules"),"two real AI chess players share local speech even with human spectating remotely")
	check(w.gomoku.memories.size()==1 and w.memories.records.any(func(entry):return entry.kind=="gomoku_match" and "human" not in entry.participants and entry.participants.size()==2),"real terminal memory records only the actual two players")
	check(w.relationships.index("npc.mira")==0 and w.relationships.index("npc.nora")==0,"spectating human receives no invented relationship progress")
	check(w.actors.human==human,"spectating human never moved or acted")
	check(w.gomoku.valid_saved(w.gomoku.saved(),w.actors,w.leisure.sites),"optional AI match source validates with unchanged memory limits")
	check(w.gomoku.begin_ai_host("play.gomoku","npc.mira","npc.nora",source).ok,"second game starts explicitly")
	g=w.gomoku.sessions["play.gomoku"];Q.advance(w,20)
	g.ai.step_limit=g.history.size()+1
	for tick in range(100):
		Q.advance(w,.2)
		if g.phase=="paused":break
	check(g.phase=="paused" and g.reason.contains("步数") and w.work.jobs.is_empty() and w.work.claims.is_empty(),"step cap pauses and releases exact jobs/seats without local substitute")
	check(Save.save_world(w,root_dir.path_join("ai")),"save real paused AI history")
	var loaded:=Q.built();check(Save.load_world(loaded,root_dir.path_join("ai")).ok,"optional schema7 AI source reloads")
	var copy: Dictionary=loaded.gomoku.sessions["play.gomoku"]
	check(copy.phase=="paused" and loaded.work.jobs.is_empty() and loaded.work.claims.is_empty() and loaded._routes.is_empty() and not copy.has("think"),"reload never restores routes/jobs/seats/thinking or budget calls")
	Q.advance(loaded,20);check(copy.history==g.history,"reloaded board never continues itself")
	check(loaded.gomoku.abandon_host("play.gomoku").ok and loaded.gomoku.memories.size()==1,"host ends unfinished game without fake win/loss memory")
	check(Save.save_world(loaded,root_dir.path_join("ended")),"save genuinely abandoned board")
	var ended:=F.fresh();check(Save.load_world(ended,root_dir.path_join("ended")).ok and ended.gomoku.sessions["play.gomoku"].phase=="abandoned","reload preserves ended status rather than reviving game")
	print("Gomoku AI rules: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
