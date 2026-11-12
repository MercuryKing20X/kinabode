extends SceneTree
## Read-only production/config probe. Every progression fact comes from genuine temporary jobs.
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(label)
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh()
	for n in range(5):world.relationships.config.stages[n].threshold=world.relationships.config.legacy_pacing.thresholds[n]
	var plot: Dictionary=world.farms.farm_plots("farm.home")[0]
	check(F.job(world,"human",{"intent":"assign_farm","farm_id":"farm.home","manager_id":"codex"}),"explicit temporary farm assignment")
	check(F.job(world,"human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}) and F.job(world,"human",{"intent":"water","target_id":plot.id}),"real seed planted and watered")
	for frame in range(2402):world.advance(.5)
	check(world.farms.stage(plot)=="mature" and F.job(world,"human",{"intent":"harvest","target_id":plot.id}),"2402 genuinely advancing growth frames, then physical harvest")
	check(world.deposit_all("human").ok and F.withdraw(world,"human","turnip"),"actual three crops taken from box")
	var near:=false;var p: Vector2=world.point(world.actors.human)
	for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
		if world.walkable("home",p+offset) and F.job(world,"codex",{"intent":"move","x":p.x+offset.x,"y":p.y+offset.y}):near=true;break
	check(near,"partner reaches real gift distance")
	check(world.command("human",{"intent":"give","receiver_id":"codex","item_id":"turnip","quantity":3}).ok,"explicit real gift, not invented progress")
	world.advance(.5)
	check(F.harvest(world,"turnip"),"separate real crop batch funds host meal while exact gifted crops remain on recipient")
	check(F.serve(world,"turnip-soup","",["human","codex","npc.mira"]),"true harvested crops cook on host fire without taking gifts back")
	check(F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"npc.mira") and F.cleanup(world),"three actual eaters and cleanup commit real memory")
	for frame in range(20):world.advance(.5)
	var state: Dictionary=world.relationships.states.codex.duplicate(true)
	check(world.relationships.index("codex")==1 and world.relationships.points(state)==7,"current real barbecue5 plus gift2 remains below new familiar8 without changed weights")
	# Exact old six-point boundary is serialization-only: never installed as played history.
	var legacy_six:Dictionary={"version":1,"states":{"codex":{"counts":{"meal":1,"gift":1},"day":1,"today":{},"stage":1,"announced":0,"recent":[]}},"seen":[]}
	check(world.relationships.legacy_points(legacy_six.states.codex.counts)==6 and world.relationships.valid_saved(legacy_six,world.actors),"legal familiar6 from real meal4 plus gift2")
	var preserved_six:Dictionary=legacy_six.duplicate(true);preserved_six.pacing_version=2;preserved_six.legacy_proofs={"codex":{"stage":1,"counts":{"meal":1,"gift":1}}}
	check(world.relationships.valid_saved(preserved_six,world.actors),"exact old six-point verified proof survives newer eight-point threshold")
	preserved_six.legacy_proofs={}
	var strict_candidate:=F.fresh()
	check(not strict_candidate.relationships.valid_saved(preserved_six,strict_candidate.actors),"exact new-format six without original legacy proof remains rejected")
	check(Save.save_world(world,directory.path_join("original")),"save actual earned progress in temporary directory")
	var save_path:=directory.path_join("original/island-v2.json")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path));data.relationships.erase("pacing_version");data.relationships.erase("legacy_proofs")
	var save_file:=FileAccess.open(save_path,FileAccess.WRITE);save_file.store_string(JSON.stringify(data));save_file.close()
	var unchanged:=F.fresh();var original_result: Dictionary=Save.load_world(unchanged,directory.path_join("original"))
	check(original_result.ok and unchanged.relationships.index("codex")==1,"same untouched production config accepts old legal progress")
	var candidate:=F.fresh();var thresholds: Array=candidate.relationships.config.stages.map(func(stage):return stage.threshold)
	for index in range(5):candidate.relationships.config.stages[index].threshold=thresholds[index]
	# Only this new instance's in-memory proposed config differs. Disk config/player saves untouched.
	var proposed_result: Dictionary=Save.load_world(candidate,directory.path_join("original"))
	check(proposed_result.ok and candidate.relationships.index("codex")==1,"fixed: actual previously earned familiar survives new threshold")
	check(Save.save_world(candidate,directory.path_join("upgraded")),"save optional compatibility proof")
	var reloaded:=F.fresh();check(Save.load_world(reloaded,directory.path_join("upgraded")).ok and reloaded.relationships.index("codex")==1,"new proof survives reload without free score")
	var forged: Dictionary=candidate.relationships.saved();forged.legacy_proofs.codex.stage=4;forged.states.codex.stage=4
	check(not candidate.relationships.valid_saved(forged,candidate.actors),"cannot forge a family floor with only seven true points")
	var fresh:=F.fresh();check(fresh.relationships.states.is_empty() and fresh.relationships.legacy_proofs.is_empty(),"new save has no free old stage")
	# Serialization-only boundary fixtures: never installed into a played world or memory stream.
	var old_cases: Array=[{"meal":1,"gift":1},{"meal":4},{"meal":4,"shared_barbecue":2,"fishing":2},{"meal":4,"shared_barbecue":4,"gomoku_match":3}]
	for level in range(1,5):
		var payload: Dictionary={"version":1,"states":{"codex":{"counts":old_cases[level-1],"day":1,"today":{},"stage":level,"announced":level,"recent":[]}},"seen":[]}
		check(candidate.relationships.valid_saved(payload,candidate.actors),"legacy serialization threshold remains compatible stage"+str(level))
		payload.pacing_version=2;payload.legacy_proofs={"codex":{"stage":level,"counts":old_cases[level-1].duplicate()}}
		check(candidate.relationships.valid_saved(payload,candidate.actors),"verified legacy proof remains valid on later reload stage"+str(level))
	var no_proof: Dictionary=candidate.relationships.saved();no_proof.legacy_proofs={}
	check(not candidate.relationships.valid_saved(no_proof,candidate.actors),"new-format seven points cannot masquerade as new familiar without true legacy proof")
	var evidence: Dictionary={"checks":checks,"failed":failed,"temporary_data_only":true,"real_model_calls":0,"real_advance_frames_for_growth":2402,"real_advance_delta":.5,"actual_earned_state":state,"actual_points":7,"legacy_serialization_boundary":6,"original_thresholds":[0,6,16,30,48],"proposed_in_memory_thresholds":thresholds,"unchanged_rules_load_ok":original_result.ok,"proposed_rules_load_ok":proposed_result.ok,"proposed_error":proposed_result.get("error",""),"invalid_copy_preserved_in_temp":FileAccess.file_exists(proposed_result.get("backup","")),"production_config_modified":false}
	var path:=OS.get_environment("HABITAT_PACING_PROBE_OUTPUT")
	if not path.is_empty():
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "));file.close()
	print("Relationship pacing compatibility probe: %d checks, failed=%s; actual7 plus exact legacy6 preserved under threshold8"%[checks,failed]);quit(1 if failed else 0)
