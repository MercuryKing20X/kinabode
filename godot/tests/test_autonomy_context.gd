extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var world:=F.fresh();world.advance(.1)
	var facts: Dictionary=world.memories.saved();var actors: Dictionary=world.actors.duplicate(true);var revision: int=world.revision
	var events: Array=[{"id":"evt","kind":"completion","text":"真事件摘要","pixels":[1,2]}]
	var history: Array=[]
	for index in range(10):history.append({"sender_id":"human","kind":"message","text":str(index)+"汉".repeat(6000),"pixels":[9]})
	for index in range(20):world.add_companion("companion-"+str(index+3),"伙伴".repeat(10))
	actors=world.actors.duplicate(true);revision=world.revision
	var context: Dictionary=world.autonomy_context("codex",events,history)
	check(context.ok and JSON.stringify(context).to_utf8_buffer().size()<=4096,"bounded UTF8 context including CJK, many residents and long histories")
	check(context.recent_dialogue.size()==3 and context.recent_dialogue[0].text.begins_with("7"),"only most recent three dialogue summaries")
	check(context.events[0].id=="evt" and not JSON.stringify(context).contains("pixels"),"event allowlist excludes raster and unrelated fields")
	check(world.actors==actors and world.memories.saved()==facts and world.revision==revision and world.work.jobs.is_empty(),"read does not mutate state, facts, jobs or revision")
	context.self.position[0]=999;context.events[0].text="changed";context.recent_dialogue.clear()
	check(world.actors.codex.position[0]!=999 and events[0].text=="真事件摘要" and history.size()==10,"deep copies world and caller-owned input")
	check(not world.autonomy_context("human").ok and not world.autonomy_context("missing").ok,"no human or unknown identity")
	world.command("codex",{"intent":"gather_wood","tree_count":1});world.advance(.1)
	check(world.autonomy_context("codex").goal.intent=="gather_wood","current accepted engine target included without full observe")
	print("Autonomy context: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
