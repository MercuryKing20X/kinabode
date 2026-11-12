extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func step(world: RefCounted,seconds: float) -> void:
	for frame in range(int(ceil(seconds/.5))):world.advance(.5)
func idle(world: RefCounted,id: String) -> void:
	world.activities.default_follow_excluded[id]=true # Isolate local wish delivery from default-follow routing.
	var r: RefCounted=world.director.routines[id];r.set_enabled(true);r.set_chatter(false)
	for key in r.preferences.weights:r.preferences.weights[key]=0
	world.days.config.small_after=world.days.day_seconds+1;world.days.config.greeting_after=world.days.day_seconds+1
func soup_only(world: RefCounted) -> void:
	world.wishes.config.templates=[world.wishes.template("soup")];world.wishes.config.first_after=1;world.wishes.next_check=0
func finish_meal(world: RefCounted) -> bool:
	return F.serve(world,"turnip-soup") and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"codex") and F.cleanup(world)
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh();world.wishes.config.first_after=1
	check(world.wishes.states.is_empty(),"new and legacy wishes start empty")
	for id in world.director.routines:idle(world,id)
	step(world,5)
	var templates: Array=world.wishes.states.values().map(func(state):return state.active.template_id)
	check(world.wishes.states.size()==4 and templates.size()==4,"one wish per each configured companion")
	var distinct: Dictionary={}
	for id in templates:distinct[id]=true
	check(distinct.size()==4,"available templates selected independently without giving four residents the same wish")
	for id in world.director.routines:
		check(world.wishes.states[id].next_day>=3 and world.wishes.states[id].next_day<=4,"next production at two/three game-day interval")
	step(world,40)
	check(world.wishes.statistics.generated.values().all(func(count):return count==1),"active wish cannot be replaced or multiplied every tick")
	check(Save.save_world(world,directory.path_join("pending")),"save genuine generated wishes")
	var loaded:=F.fresh();check(Save.load_world(loaded,directory.path_join("pending")).ok,"reload pending wishes")
	check(loaded.wishes.active("codex").id==world.wishes.active("codex").id and loaded.wishes.states.size()==4,"unfinished desires preserve identity across reload without any work")
	var invalid: Dictionary=world.wishes.saved();invalid.states.codex.active.resident_id="human"
	check(not world.wishes.valid_saved(invalid,world.actors),"cross-actor wish cannot be forged")
	var count_mem: int=world.memories.records.size();world.advance(world.days.day_seconds*5);step(world,2)
	check(world.wishes.statistics.expired.values().reduce(func(total,value):return total+value,0)==4 and world.memories.records.size()==count_mem,"five-day expiry fades with no failure memory or reward")
	# Only actual newly eaten food may fulfill the meal goal, never preparation/invitation.
	world=F.fresh();check(F.harvest(world,"turnip"),"real crops before meal wish")
	check(preload("res://tests/local_life2_fixture.gd").shared_catch(world),"real second activity before new familiar threshold")
	soup_only(world);idle(world,"codex");step(world,2)
	check(not world.wishes.active("codex").is_empty() and world.wishes.active("codex").proof_id.is_empty(),"realistic meal wish has no initial completion")
	check(F.serve(world,"turnip-soup"),"real cooking served")
	step(world,2);check(world.wishes.active("codex").proof_id.is_empty(),"serving or invitation alone never means eaten")
	check(F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"codex") and F.cleanup(world),"both actually finish food and cleanup")
	step(world,2);check(not world.wishes.active("codex").proof_id.is_empty() and not world.memories.records.any(func(entry):return entry.kind=="wish_completed"),"real proof awaits actual permitted local reaction")
	world.relationships.config.stage_events_enabled=false
	var r: RefCounted=world.director.routines.codex;r.set_chatter(true);step(world,100)
	var records: Array=world.memories.records.filter(func(entry):return entry.kind=="wish_completed")
	check(records.size()==1 and world.wishes.active("codex").is_empty(),"actual local reaction commits one completion and clears wish")
	check(world.director.events.any(func(event):return event.source=="local_rules" and event.context=="wish_completed"),"reaction is clearly local through shared outlet")
	check(world.relationships.states.codex.counts.wish_completed==1 and world.relationships.index("codex")==1,"true completed wish adds bounded relationship progress")
	check(F.amount(world,"turnip")==0 and world.actors["npc.mira"].carry.is_empty(),"no wish material reward or local inventory grant")
	world.director.memory_reminders.config.min_age=0
	check(not records.is_empty() and world.director.memory_reminders.text_for("codex",records[0]).contains("萝卜") and world.director.memory_reminders.text_for("companion-2",records[0]).is_empty(),"existing reminders use only actual owner's fulfilled wish")
	check(world.memories.valid_saved(world.memories.saved(),world.actors,world.world_id),"new canonical memory respects unchanged capacity/validation")
	var context: Dictionary=world.autonomy_context("codex");check(context.self.has("wish") and JSON.stringify(context).to_utf8_buffer().size()<=4096,"small read-only future model summary, no trigger")
	# A wish generated after an old meal must not claim the meal retroactively.
	world=F.fresh();check(F.harvest(world,"turnip") and finish_meal(world),"real earlier meal fixture")
	soup_only(world);idle(world,"codex");step(world,4)
	check(not world.wishes.active("codex").is_empty() and world.wishes.active("codex").proof_id.is_empty(),"previous completed activity excluded by generation baseline")
	check(Save.save_world(world,directory.path_join("old")),"save old optional-field fixture")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("old/island-v2.json")));data.erase("wishes")
	var file:=FileAccess.open(directory.path_join("old/island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	loaded=F.fresh();check(Save.load_world(loaded,directory.path_join("old")).ok and loaded.wishes.states.is_empty(),"old save stays empty, no free wish/history")
	print("Wishes: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
