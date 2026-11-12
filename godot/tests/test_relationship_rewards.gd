extends SceneTree
const R=preload("res://tests/relationship_reward_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func run() -> void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(1);return
	var world:=F.fresh();var cfg:=ConfigFile.new();world.relationships.setup_preferences(cfg,dir.path_join("local-life.cfg"))
	check(not world.relationships.set_address("codex","队长") and not world.relationships.reward("codex","sit"),"initial acquaintance cannot unlock nickname or sitting reward")
	for level in range(1,5):
		world=R.load_stage(level)
		if world==null:quit(1);return
		check(world.relationships.index("codex")==level,"checkpoint has genuinely earned stage"+str(level))
		world.relationships.setup_preferences(cfg,dir.path_join("local-life.cfg"))
		check(R.camp(world),"genuine physical QA arrival near camp")
		R.ready(world);var human: Dictionary=world.actors.human.duplicate(true)
		check(world.relationships.set_address("codex","队长") and not world.relationships.set_address("codex","x\ny"),"bound nickname saved, multiline refused")
		check(world.relationships.addressed("codex",world.relationships.config.lines.passing).all(func(line):return line.contains("队长")),"familiar remembers actual preferred address")
		check(world.relationships.address("companion-2")!="队长","address preference is independent per resident")
		check(world.relationships.reward("codex","passing") and world.director.events[-1].source=="local_rules" and world.director.events[-1].text.contains("队长"),"passing greeting pauses through shared local outlet")
		world.director.routines.codex.interrupt(0)
		if level==1:check(not world.relationships.reward("codex","sit") and world.relationships.our_place("codex").is_empty(),"low stage cannot get close seat or attuned place")
		else:
			check(world.relationships.reward("codex","sit"),"close or higher uses original free nearby seat")
			R.step(world,5);check(world.director.routines.codex.kind=="rest" and not world.director.routines.codex.seat_id.is_empty(),"real arrival and exact seat ownership")
			world.director.routines.codex.interrupt(0)
		if level>=3:
			var place: Dictionary=world.relationships.our_place("codex")
			check(not place.is_empty() and place.evidence_count>0,"our place derives retained actual shared memories")
			check(world.schedules.options("codex").any(func(option):return option.place=="our_place"),"attuned shared place is an actual idle schedule preference")
			check(world.command("human",{"intent":"gather_wood","tree_count":1}).ok,"human explicitly accepts real work")
			var job: String=str(world.work.jobs.get("human",{}).get("id",""))
			var human_route: Array=world._routes.get("human",[]).duplicate(true)
			check(world.relationships.work_context()=="chop" and world.relationships.reward("codex","work"),"attuned actual chopping selects accompaniment")
			check(world._routes.get("human",[])==human_route,"accompaniment leaves human route untouched")
			R.step(world,1);check(world.work.jobs.get("human",{}).get("id")==job,"companion does not steal or stop human task")
			check(F.wait(world,"human"),"real human work finishes")
			for context in ["chop","fish","cook","farm"]:check(world.relationships.config.rewards.work_lines[context].size()>=4,"work has dedicated authored pool "+context)
			world.director.routines.codex.interrupt(0)
			check(R.camp(world),"explicit QA return after finished human work")
			human=world.actors.human.duplicate(true)
		if level<4:check(world.relationships.book("codex").is_empty(),"our days locked below family")
		else:
			var book: Array=world.relationships.book("codex");check(not book.is_empty() and book.all(func(entry):return world.memories.records.any(func(record):return record.id==entry.id)),"family book only retained real memories")
			world.relationships.returned.codex=true
			check(world.relationships.reward("codex","welcome"),"family returns welcome moves companion alone")
			world.director.routines.codex.interrupt(0)
		check(world.actors.human==human,"ordinary reward never automatically moves human")
		check(world.actors.codex.carry.is_empty(),"reward never creates or takes items")
		check(Save.save_world(world,dir.path_join("stage"+str(level))),"save reward world optional compatibility")
		var loaded:=F.fresh();check(Save.load_world(loaded,dir.path_join("stage"+str(level))).ok and loaded.relationships.index("codex")==level,"reload preserves earned unlock and restores no jobs")
		var settings:=ConfigFile.new();settings.load(dir.path_join("local-life.cfg"));loaded.relationships.setup_preferences(settings,dir.path_join("local-life.cfg"))
		check(loaded.relationships.address("codex")=="队长","nickname survives reload in existing config, not session history")
		var actor: RefCounted=world.director.routines.codex;actor.set_held(true)
		check(not world.relationships.reward("codex","passing"),"held never bypassed by reward")
		actor.set_held(false);world.command("codex",{"intent":"stop"})
		R.step(world,119);check(not world.relationships.reward("codex","passing"),"stop120s retains quiet gate")
	print("Relationship rewards: %d checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
