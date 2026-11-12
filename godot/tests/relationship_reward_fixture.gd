extends RefCounted
const Places=preload("res://scripts/map_locations.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
static func directory() -> String:
	var evidence:=ProjectSettings.globalize_path("res://../production/evidence/local-life-2-2026-10-27/real-stage-fixtures")
	if FileAccess.file_exists(evidence.path_join("stage4/island-v2.json")):return evidence
	var temporary: String=OS.get_environment("HABITAT_DATA_DIR").path_join("earned-fixtures")
	if not FileAccess.file_exists(temporary.path_join("stage4/island-v2.json")):
		OS.set_environment("HABITAT_LIFE2_EXTENDED","1");OS.set_environment("HABITAT_LIFE2_STAGE_SAVES",temporary);OS.set_environment("HABITAT_LIVE_TEST","0")
		var output: Array=[]
		var code:=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","tests/test_local_life_15d.gd"],output,true)
		if code!=0:push_error("Real stage fixture creation failed: "+str(output))
		OS.set_environment("HABITAT_LIFE2_EXTENDED","");OS.set_environment("HABITAT_LIFE2_STAGE_SAVES","")
	return temporary
static func load_stage(level: int) -> RefCounted:
	var world:=F.fresh()
	if not Save.load_world(world,directory().path_join("stage"+str(level))).get("loaded",false):push_error("Missing genuine stage checkpoint; run extended test_local_life_15d with HABITAT_LIFE2_STAGE_SAVES");return null
	prepare(world)
	return world
static func prepare(world: RefCounted) -> void:
	world.director.set_all_enabled(false)
	for who in ["human","codex"]:
		var fish: Dictionary=world.fishing.held(who)
		if not fish.is_empty():world.command(who,{"intent":"stock_fish","fish_id":fish.id,"pen_id":world.fishing.pens.keys()[0]})
		if not world.actors[who].carry.is_empty():F.job(world,who,{"intent":"store"})
	for id in world.director.routines:
		if id=="codex":continue
		var p: Array=world.residents.definitions[id].position
		F.job(world,id,{"intent":"move","x":p[0],"y":p[1]})
	world.days.config.greeting_after=world.days.day_seconds+1;world.days.config.small_after=world.days.day_seconds+1
	world.relationships.config.stage_events_enabled=false
static func step(world: RefCounted,seconds: float) -> void:
	for frame in range(int(ceil(seconds/.5))):world.advance(.5)
static func camp(world: RefCounted) -> bool:
	for p in [Places.point("p_24_50"),Places.point("p_24_49"),Places.point("p_24_48"),Places.point("p_23_50")]:
		if not world.walkable("home",p):continue
		if not F.job(world,"human",{"intent":"move","x":p.x,"y":p.y}):continue
		for offset in [Vector2(0,2.5),Vector2(2,1.5),Vector2(-2,1.5)]:
			if world.walkable("home",p+offset) and F.job(world,"codex",{"intent":"move","x":p.x+offset.x,"y":p.y+offset.y}):return true
	return false
static func ready(world: RefCounted) -> void:
	# C: Isolate a granted local seat reward from automatic default follow.
	world.activities.default_follow_excluded.codex=true;world.activities.release_follow("codex")
	var r: RefCounted=world.director.routines.codex;r.set_enabled(true);r.set_chatter(true)
	for key in r.preferences.weights:r.preferences.weights[key]=0
	r.next_speech=0;r.next_decision=INF;world.director.speech_after=0
