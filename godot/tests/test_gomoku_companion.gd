extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Rules=preload("res://scripts/gomoku_rules.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func step(w: RefCounted,seconds: float) -> void:
	for i in range(int(ceil(seconds/.5))):w.advance(.5)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var w:=F.fresh();w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));w.library.resident_world=w
	var c: RefCounted=w.gomoku.companion;c.observe("play.gomoku")
	c.config.player_wait=3600;c.config.long_think=3600
	check(c.valid(c.config),"all four personalities have four lines in every chess context")
	check(c.pool("codex","start")!=c.pool("npc.mira","start"),"different personalities select different authored chess pools")
	check(F.job(w,"codex",{"intent":"gather_wood","tree_count":10}) and F.job(w,"codex",{"intent":"build_facility","target_id":"play.gomoku"}),"real wood builds actual chess table")
	check(w.gomoku.begin_host("play.gomoku","codex",true,"local","easy").ok,"explicit host starts real seated match")
	if not w.gomoku.sessions.has("play.gomoku"):quit(1);return
	var g: Dictionary=w.gomoku.sessions["play.gomoku"]
	for tick in range(240):
		step(w,.5)
		if g.phase=="playing":break
	check(g.phase=="playing","genuine advance reaches both real seats")
	var r: RefCounted=w.director.routines.codex;r.set_enabled(true);r.set_chatter(true)
	step(w,50)
	check(c.say("codex",g,"start"),"eligible chess line delivered through shared outlet")
	check(not c.say("codex",g,"move") and not c.preset(g,0),"at most one delivered line per hand, including preset responses")
	check(not c.bubble(g,"codex").is_empty() and c.bubble(g,"codex").source=="local_rules","portrait receives same real local text")
	var used: String=c.bubble(g,"codex").text
	c.state(g).hand=-1;step(w,50);r.set_chatter(false)
	check(not c.say("codex",g,"start"),"chatter off suppresses chess speech")
	r.set_chatter(true);r.set_held(true);step(w,20)
	check(not c.say("codex",g,"start"),"held pending answer suppresses chess speech")
	r.set_held(false);step(w,50)
	check(c.say("codex",g,"start") and c.bubble(g,"codex").text!=used,"used phrase never repeats within same match")
	w.command("codex",{"intent":"stop"});step(w,30)
	check(not c.say("codex",g,"start"),"stop quiet period and paused match cannot talk")
	# Pure legal replay probes expose the same evaluator's facts; no played memories are fabricated.
	var probe: Dictionary=g.duplicate(true);probe.id="probe";probe.history=[[6,7],[1,1],[7,7],[2,1],[8,7]];probe.revision+=1
	check(c.facts(probe).open_three and c.context(probe,"codex","move")=="open_three","real open-three pattern selects open-three pool")
	probe.history.append([3,1]);probe.history.append([9,7]);probe.revision+=1
	check(c.facts(probe).four,"actual four pattern selects four pool")
	probe.history=[[5,7],[1,1],[6,7],[2,1],[7,7],[3,1],[8,7],[9,7]];probe.revision+=1
	check(c.facts(probe).blocked,"blocking a genuine four derives from prior Rules.value")
	var art: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/white-haired-girl.json"))
	for pose in c.config.frames:check(art.frames.has(c.frame(art,pose)),"missing optional expression safely falls back "+pose)
	check(c.frame(art,"think")!=c.frame(art,"move") and c.frame(art,"win")!=c.frame(art,"lose"),"existing artwork switches actual different thinking/move/win/lose frames")
	var custom:=art.duplicate(true);custom.frames.gomoku_think=custom.frames.down_0.duplicate(true)
	check(c.frame(custom,"think")=="gomoku_think","authored optional custom expression wins over fallback")
	probe.phase="finished";probe.result="draw"
	check(c.pose(probe,"codex")=="draw","draw pose independent of absent optional art")
	probe.result="five";probe.winner_id="codex"
	check(c.pose(probe,"codex")=="win" and c.pose(probe,"human")=="lose","true winner drives terminal poses")
	check(w.gomoku.memories.is_empty(),"read-only board probes never create fake match memories")
	print("Gomoku companion: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
