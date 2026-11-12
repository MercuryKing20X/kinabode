extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const MF=preload("res://tests/resident_mood_fixture.gd")
const S=preload("res://scripts/save_store.gd")
const W=preload("res://scripts/world_state.gd")
# Independent dialogue sources are tested in their own integration suites.
# Keep this probe about the derived-mood pool and its unchanged cadence multiplier.
class NoNeeds extends "res://scripts/resident_needs.gd":
	func choose(_world:RefCounted,_id:String)->Dictionary:return {}
class NoScenes extends "res://scripts/scene_speech.gd":
	func choose(_id:String)->Dictionary:return {}
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func advance(world: RefCounted,seconds: float) -> void:
	for tick in range(int(ceil(seconds/.5))):world.advance(minf(.5,seconds-tick*.5))
func shared_meal(world: RefCounted) -> bool:
	return MF.shared_meal(world)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var world:=F.fresh();var moods: Variant=world.director.get("moods")
	check(moods!=null,"same partner must derive distinct mood and line pools from different real inputs")
	if moods==null:
		print("Resident moods RED: %s checks, failed=%s"%[checks,failed]);quit(1);return
	world.advance(.1)
	var before: Dictionary=moods.summary("codex");var before_lines: Array=moods.lines("codex")
	check(shared_meal(world),"genuine completed shared meal supplies happiness fact")
	moods.player_input();advance(world,2.2)
	check(before.id=="calm" and moods.summary("codex").id=="happy","same resident changes calm to happy after actual shared meal")
	check(before_lines!=moods.lines("codex"),"different factual inputs select different mood line pools")
	var base: Dictionary=world.director.routines.codex.preferences.weights.duplicate(true)
	var happy_weights: Dictionary=moods.weights("codex",base)
	check(happy_weights.facility>base.facility and happy_weights.nearby>base.nearby and world.director.routines.codex.preferences.weights==base,"happy changes effective social choice weights without rewriting resident preferences")
	var state: Dictionary=moods.summary("codex");var changed: float=moods.changed_at.codex
	var stable:=true
	for frame in range(600):world.advance(.1);stable=stable and moods.summary("codex")==state
	check(stable,"same real inputs keep same mood for all600 advancing frames")
	check(moods.changed_at.codex==changed,"same inputs never retrigger transitions each frame")
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	check(S.save_world(world,directory.path_join("happy")),"save actual shared meal without mood persistence")
	var serialized: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("happy/island-v2.json")))
	check(serialized.schema_version==7 and not serialized.has("moods") and not serialized.actors.codex.has("mood"),"schema7 has no emotion fields")
	var restored:=W.new();restored.residents.provision(restored)
	check(S.load_world(restored,directory.path_join("happy")).ok,"reload real shared facts")
	advance(restored,2.2);check(restored.director.moods.summary("codex").id=="happy","recent genuine shared event reconstructs happiness after reload")
	var other: Dictionary=moods.summary("companion-2")
	check(other.id!="happy","nonparticipant never inherits another pair's shared happiness")
	inactivity();work_and_reload();speech_guards();retention()
	print("Resident moods: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
func inactivity() -> void:
	var world:=F.fresh();var moods: RefCounted=world.director.moods
	world.director.routines.codex.held=true
	advance(world,1202)
	check(moods.summary("codex").id=="quiet" and moods.summary("codex").reason=="玩家暂未操作","20 minutes without physical input derives quiet even while held")
	check(moods.lines("codex")==moods.config.states.quiet.lines,"inactive player uses quiet authored pool")
	var quiet: Dictionary=moods.summary("codex");var changed: float=moods.changed_at.codex
	for frame in range(600):world.advance(.1)
	check(moods.summary("codex")==quiet and moods.changed_at.codex==changed,"600-frame inactive state remains stable")
	moods.player_input();advance(world,16)
	check(moods.summary("codex").id=="quiet" and moods.summary("codex").reason=="夜晚","real night remains quiet after input, not artificial loneliness")
	# DayCycle's existing projection is the only calendar; advance through next morning.
	advance(world,260);moods.player_input();advance(world,16)
	check(world.days.phase().id=="morning" and moods.summary("codex").id=="calm","next real morning plus player input returns calm")
	var empty:=F.fresh();advance(empty,61)
	check(empty.director.moods.summary("codex").id=="calm" and empty.memories.records.is_empty(),"no shared facts never invent happy history")
func work_and_reload() -> void:
	var world:=F.fresh();var control:=F.fresh();control.director.moods.config.tired_after=86400
	var moods: RefCounted=world.director.moods;var human: Dictionary=world.actors.human.duplicate(true)
	# No box round trips now: use genuine additional continuous harvesting to
	# exercise the unchanged 180-second observed labor threshold.
	check(world.command("codex",{"intent":"gather_wood","tree_count":12}).ok and control.command("codex",{"intent":"gather_wood","tree_count":12}).ok,"same genuine preparation preserves tiredness threshold coverage")
	var preparation_identical:=true
	for tick in range(20000):
		world.advance(.1);control.advance(.1)
		preparation_identical=preparation_identical and world.actors.codex.position==control.actors.codex.position and world.actors.codex.activity==control.actors.codex.activity
		if not world.work.jobs.has("codex") and not control.work.jobs.has("codex"):break
	check(world.command("codex",{"intent":"build_house","target_id":"home.house.01"}).ok and control.command("codex",{"intent":"build_house","target_id":"home.house.01"}).ok,"explicit same real construction accepted with or without tiredness")
	var tired:bool=moods.summary("codex").id=="tired";var identical:bool=preparation_identical
	for tick in range(20000):
		world.advance(.1);control.advance(.1)
		identical=identical and world.actors.codex.position==control.actors.codex.position and world.actors.codex.activity==control.actors.codex.activity
		if moods.summary("codex").id=="tired":tired=true
		if world.projects.plans.codex.status=="completed" and control.projects.plans.codex.status=="completed":break
	check(tired,"real continuous physical work exceeds default180 second threshold")
	check(world.projects.plans.codex.status=="completed" and world.objects["home.house.01"].stage_index==5,"tired resident still actually finishes full house")
	check(identical and world.objects["home.house.01"].invested==control.objects["home.house.01"].invested and world.drops==control.drops,"mood changes no frame of movement, job progress or physical material cost")
	check(world.actors.human==human,"mood never moves or operates human")
	check(moods.interval("codex","speech")>1 and moods.interval("codex","action")>1,"tiredness slows only idle speech and decision intervals")
	var base: Dictionary=world.director.routines.codex.preferences.weights
	check(moods.weights("codex",base).wander<base.wander and moods.weights("codex",base).rest>base.rest,"tired idle weights prefer rest over walking")
	var routine: RefCounted=world.director.routines.codex;var comparison: RefCounted=control.director.routines.codex
	for key in routine.preferences.weights:routine.preferences.weights[key]=0;comparison.preferences.weights[key]=0
	routine.last_walk=0;comparison.last_walk=0;routine.rng.seed=7;comparison.rng.seed=7
	routine._choose();comparison._choose()
	check(routine.next_decision-routine.time>comparison.next_decision-comparison.time,"actual local decision timer grows when tired under identical RNG")
	if not world.actors.codex.carry.is_empty():check(F.job(world,"codex",{"intent":"store","target_id":"home.chest.01"}),"real surplus wood stored before tired idle speech")
	check(F.job(world,"codex",{"intent":"come_near"}),"explicitly return tired worker near human before speech probe")
	advance(world,16)
	ready(world);world.advance(.1)
	check(not world.director.events.is_empty() and world.director.events[-1].text in world.personality.pool("codex","tired"),"actually tired resident still speaks its own pool once idle")
	check(routine.next_speech-routine.time>=float(routine.config.speech_interval[0])*moods.interval("codex","speech")*world.personality.speech_scale("codex") and routine.next_speech-routine.time<=float(routine.config.speech_interval[1])*moods.interval("codex","speech")*world.personality.speech_scale("codex"),"actual scheduled speech interval is longer, not a mute or task delay")
	check(S.save_world(world,OS.get_environment("HABITAT_DATA_DIR").path_join("tired")),"save completed real labor")
	check(S.load_world(control,OS.get_environment("HABITAT_DATA_DIR").path_join("tired")).ok and control.director.moods.labor.is_empty(),"in-place successful reload also clears unrecorded observation timers")
	var restored:=W.new();restored.residents.provision(restored)
	check(S.load_world(restored,OS.get_environment("HABITAT_DATA_DIR").path_join("tired")).ok,"reload stops labor and its session observation")
	advance(restored,2.2)
	check(restored.director.moods.summary("codex").id!="tired" and restored.work.jobs.is_empty(),"reload does not invent an unrecorded work duration or restart jobs")
	check(world.command("codex",{"intent":"gather_wood","tree_count":1}).ok,"still-tired resident accepts next explicit task without refusal")
	check(F.wait(world,"codex"),"next explicit job progresses normally while tired")
	advance(world,80)
	check(moods.summary("codex").id!="tired","real rest clears transient labor observation without energy bar")
func ready(world: RefCounted) -> void:
	MF.idle(world)
	world.director.routines.codex.needs=NoNeeds.new()
	world.scene_speech=NoScenes.new(world)
func speech_guards() -> void:
	for condition in ["chatter","held","pending","assembly","stop","personal","village"]:
		var world:=F.fresh();ready(world);advance(world,1202)
		var routine: RefCounted=world.director.routines.codex
		world.director.events.clear();routine.events.clear();routine.next_speech=0;world.director.speech_after=0
		match condition:
			"chatter":routine.chatter=false
			"held":world.director.set_held("codex",true)
			"pending":world.activities.held["codex"]=true
			"assembly":world.activities.gather()
			"stop":world.command("codex",{"intent":"stop"})
			"personal":routine.next_speech=routine.time+10
			"village":world.director.speech_after=world.director.time+10
		advance(world,2)
		check(world.director.events.is_empty(),"mood speech obeys "+condition)
		check(world.director.moods.summary("codex").id=="quiet","mood derivation continues under "+condition)
	var world:=F.fresh();ready(world);world.advance(.1)
	check(world.director.events.size()==1 and world.director.events[0].text in world.personality.pool("codex","ambient") and world.director.events[0].source=="local_rules","actual idle tick speaks mood-authored line through shared outlet once")
	check(world.local_companion.events.size()==1,"existing local receipt retained without double delivery")
func retention() -> void:
	var world:=F.fresh();check(shared_meal(world),"genuine event before bounded-memory retention test")
	world.director.moods.player_input();advance(world,2.2)
	check(world.director.moods.summary("codex").id=="happy","genuine retained event supplies happiness")
	check(world.life.fireside.state.committed and world.life.fireside.state.ate.has("codex") and "codex" in world.life.fireside.state.current.eaters,"real current barbecue consumption source remains independently retained")
	# Fault fixture simulates canonical eviction, not invented events or resources.
	world.memories.records.clear();advance(world,18)
	check(world.director.moods.summary("codex").id!="happy","does not reconstruct emotion from evicted historical source")
