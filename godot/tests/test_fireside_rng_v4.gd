extends SceneTree
## Logic/Integration — production/evidence/barbecue-v4 — BLOCKING deterministic local presentation.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
class NoNeeds extends "res://scripts/resident_needs.gd":
	func choose(_world:RefCounted,_id:String)->Dictionary:return {}
class NoScenes extends "res://scripts/scene_speech.gd":
	func choose(_id:String)->Dictionary:return {}
func isolated()->RefCounted:
	var world:RefCounted=F.fresh()
	# The original ordinary outlet unit owns a free-idle scene. Optional new dialogue
	# has its own real-input/600s tests; keep all ordinary due/RNG/proof assertions.
	world.director.local_dialogue.next_check=INF
	for id in world.director.routines:
		world.activities.release_follow(id);world.activities.default_follow_excluded[id]=true
	for r in world.director.routines.values():r.needs=NoNeeds.new()
	world.scene_speech=NoScenes.new(world)
	return world
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	speech_rejection()
	idle_order()
	idle_priority()
	context_rejection()
	relationship_pool_fallback()
	var authority:=F.fresh();var legacy:RefCounted=authority.life.fireside.dialogue
	check(legacy.trait_id("npc.mira")==authority.intelligence.tag("npc.mira") and legacy.trait_id("companion-2")==authority.intelligence.tag("companion-2"),"legacy compatibility dialogue uses current authored intelligence authority")
	authority.intelligence.activate_presets()
	check(legacy.trait_id("npc.mira")==authority.intelligence.tag("npc.mira") and legacy.trait_id("companion-2")==authority.intelligence.tag("companion-2"),"layered presets dialogue follows actual current assigned trait after activation")
	var samples:Array=[]
	for index in range(2):
		var w:=isolated();w.world_id="00000000-0000-4000-8000-000000001027"
		var before:Dictionary=w.actors.duplicate(true);var revision:int=w.revision
		var d:RefCounted=w.life.fireside.dialogue;d.tick()
		samples.append({"seed":str(d.rng.seed),"state":str(d.rng.state),"topic":d.mini_topic,"mini_left":d.mini_left})
		check(w.actors==before and w.work.jobs.is_empty() and w.revision==revision,"presentation RNG initializes without world/resource or human action "+str(index))
	check(samples[0]==samples[1],"two identical retained world/station keys produce identical first dialogue sequence")
	var w:=isolated();w.world_id="00000000-0000-4000-8000-000000001027";var d:RefCounted=w.life.fireside.dialogue;d.tick();var state:int=d.rng.state;d.tick()
	check(d.rng.state==state,"ordinary repeated tick does not reseed or redraw inactive empty circle")
	w.world_id="00000000-0000-4000-8000-000000001028";d.tick()
	check(d.rng.seed==hash(w.world_id+":"+str(w.life.station.id)+":fireside-v4"),"changed retained world selects its exact versioned station key")
	# Real recipe meal must feed existing personality factual outlet, never invent a dinner.
	w=isolated();check(F.harvest(w,"turnip") and BBQ.meal(w,"recipe:turnip-soup",["human","codex"]),"actual crop recipe and invited eaters produce real canonical barbecue")
	for tick in range(10):w.advance(.5)
	var fact:Dictionary=w.personality.factual("codex")
	check(fact.get("context")=="meal" and not fact.get("key","").is_empty(),"actual shared-barbecue recipe enters original authored meal reaction")
	check(w.personality.factual("companion-2").get("context")!="meal","uninvited bystander never claims the same meal reaction")
	var r:RefCounted=w.director.routines.codex
	check(F.job(w,"human",{"intent":"move","x":w.point(w.actors.codex).x+2,"y":w.point(w.actors.codex).y}),"actual host return puts real meal participant within factual speech distance")
	r.enabled=true;r.chatter=true;r.next_decision=INF;r.next_speech=0.
	var rng_state:int=r.rng.state;var facts_before:Dictionary=w.memories.saved()
	w.director.speech_after=w.director.time+14.
	check(not w.personality.try_event("codex") and r.rng.state==rng_state,"real meal factual reaction rejected by original village gate consumes no authored RNG")
	check(r.next_speech==0. and fact.key not in w.personality.reacted and w.memories.saved()==facts_before,"undelivered meal reaction consumes no personal cooldown fact mark or history")
	w.director.speech_after=0.;r.next_speech=r.time+12.
	check(not w.personality.try_event("codex") and r.rng.state==rng_state and fact.key not in w.personality.reacted,"real meal factual reaction rejected by original personal gate consumes no authored RNG or proof")
	r.next_speech=0.;r.enabled=false
	var entry:Dictionary=w.read_memories("human",{"kind":"shared_barbecue"}).memories[0]
	check(fact.get("key")==("codex:meal:"+entry.id).sha256_text(),"new recipe shares exact original canonical deduplication key")
	w.personality.reacted.append(fact.key);check(w.personality.factual("codex").get("context")!="meal","reacted canonical meal cannot repeat through a new source alias")
	w.personality.reacted.clear();w.personality.reset();check(w.personality.factual("codex").get("context")!="meal","reload baseline never replays retained completed dinner")
	print("Fireside RNG and recipe facts v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

func speech_rejection()->void:
	# Actual travel establishes the same listener-distance failure, with no position injection.
	var w:=isolated();var r:RefCounted=w.director.routines["npc.mira"]
	check(Fish.walk(w,"human",[27,44]),"host actually walks beyond ambient listener radius")
	r.enabled=true;r.chatter=true;r.held=false;r.time=1000.;r.next_speech=0.;r.next_decision=100000.;r.rng.seed=123456
	w.director.time=1000.;w.director.speech_after=0.
	var state:int=r.rng.state;var actor_snapshot:Dictionary=w.actors.duplicate(true)
	var serial:int=w.director.serial
	check(w.point(w.actors.human).distance_to(w.point(w.actors["npc.mira"]))>12. and w.director.moods.can_speak("npc.mira"),"far speaker is otherwise eligible under original local gates")
	r._speak("ambient")
	check(w.director.serial==serial,"far ambient attempt never reaches visible delivery")
	check(r.next_speech==0. and r.rng.state==state,"distance rejection consumes neither personal cooldown nor authored RNG sequence")
	check(w.actors==actor_snapshot and w.work.jobs.is_empty(),"rejected speech never moves human or changes actual work")
	r.enabled=false
	var point:Vector2=w.point(w.actors["npc.mira"])
	check(Fish.walk(w,"human",[point.x+2.,point.y]),"host returns within two cells by original World route")
	r.enabled=true;r._speak("ambient")
	check(w.director.serial==serial+1 and r.next_speech>r.time and r.rng.state!=state,"returning nearby can really deliver immediately and only then consumes personal cadence")
	state=r.rng.state;serial=w.director.serial;r._speak("ambient")
	check(w.director.serial==serial and r.rng.state==state,"original delivered personal cooldown still rejects a second immediate line without RNG draw")
	r.next_speech=0.;state=r.rng.state;r._speak("ambient")
	check(w.director.serial==serial,"original shared village gate still prevents another visible delivery")
	check(r.rng.state==state and r.next_speech==0.,"village rejection consumes no authored RNG or undelivered personal turn")

func idle_order()->void:
	for due in [{"codex":900.,"companion-2":800.,"npc.mira":700.},{"codex":800.,"companion-2":700.,"npc.mira":900.},{"codex":700.,"companion-2":900.,"npc.mira":800.},{"codex":700.,"companion-2":700.,"npc.mira":700.}]:
		var w:=isolated()
		for id in due:check(F.job(w,id,{"intent":"come_near"}),"real nearby idle arbitration setup "+id)
		var expected:String=""
		for id in due:
			var r:RefCounted=w.director.routines[id]
			r.enabled=true;r.chatter=true;r.held=false;r.time=1000.;r.next_decision=INF;r.next_speech=due[id];r.rng.seed=27;r.was_busy=false
			# Consume only this fixture's current optional weather reaction to isolate ordinary idle speech.
			w.personality.reacted.append((id+":"+str(w.days.day())+":"+w.weather.current().id).sha256_text())
			if expected.is_empty() or float(due[id])<float(due[expected]):expected=id
		w.director.time=1000.;w.director.speech_after=0.;w.director.events.clear()
		var actors:Dictionary=w.actors.duplicate(true);w.director.advance(.5)
		check(w.director.events.size()==1 and w.director.events[0].actor_id==expected,"ordinary idle outlet serves earliest existing personal due time: "+expected)
		check(w.director.events.size()==1 and w.director.events[0].context in ["ambient","near"],"idle arbitration retains one real ordinary line and original village outlet")
		check(w.actors==actors and w.work.jobs.is_empty(),"idle arbitration never moves human or creates a physical job")

func idle_priority()->void:
	for condition in ["held","event"]:
		var w:=isolated();var due:Dictionary={"codex":900.,"companion-2":800.,"npc.mira":700.}
		if condition=="event":check(F.harvest(w,"turnip") and BBQ.meal(w,"recipe:turnip-soup",["human","codex"]),"real current crop meal supplies factual priority instead of a randomly rainy day")
		for id in due:check(F.job(w,id,{"intent":"come_near"}),"actual nearby arbitration priority setup "+condition+":"+id)
		for id in due:
			var r:RefCounted=w.director.routines[id];r.enabled=true;r.chatter=true;r.time=1000.;r.next_decision=INF;r.next_speech=due[id];r.rng.seed=27;r.was_busy=false;r.kind="";r.owned_job_id="";r.visual_quiet_until=0.;w.fishing.life.quiet_until.erase(id);w.hunger.quiet_until.erase(id)
			if condition=="held" or id!="codex":w.personality.reacted.append((id+":"+str(w.days.day())+":"+w.weather.current().id).sha256_text())
		if condition=="held":w.director.routines["npc.mira"].held=true
		if condition=="event":w.days.marked_day=w.days.day();w.days.spoken.append(w.days.phase().id);w.days.small={"status":"completed"}
		w.director.time=1000.;w.director.speech_after=0.;w.director.events.clear();w.director.advance(.5)
		if condition=="held":check(w.director.events.size()==1 and w.director.events[0].actor_id=="companion-2","held oldest speaker cannot participate; next eligible existing due wins")
		else:check(w.director.events.size()==1 and w.director.events[0].actor_id=="codex" and w.director.events[0].context.begins_with("personality_"),"true authored factual event retains priority over collected ordinary idle candidates")

func context_rejection()->void:
	var w:=isolated();check(F.job(w,"npc.mira",{"intent":"come_near"}),"actual near scene before full idle tick rejection")
	var r:RefCounted=w.director.routines["npc.mira"]
	r.enabled=true;r.chatter=true;r.held=false;r.time=1000.;r.next_decision=INF;r.next_speech=0.;r.rng.seed=27;r.was_busy=false
	w.personality.reacted.append(("npc.mira:"+str(w.days.day())+":"+w.weather.current().id).sha256_text())
	w.director.time=1000.;w.director.speech_after=1014.
	var state:int=r.rng.state;w.director.advance(.5)
	check(w.director.events.is_empty() and r.next_speech==0.,"full local tick still obeys village gate without imaginary delivered turn")
	check(r.rng.state==state,"full rejected local tick does not draw ordinary context from shared behavior RNG before speech eligibility")

func wait_speech_gate(w:RefCounted,r:RefCounted)->void:
	r.enabled=false
	var pause:float=maxf(0.,maxf(r.next_speech-r.time,w.director.speech_after-w.director.time))+.1
	for tick in range(int(ceil(pause/.1))):w.advance(.1)
	r.enabled=true

func relationship_pool_fallback()->void:
	var w:=isolated()
	check(F.mushroom(w) and BBQ.meal(w,"single:mushroom",["human","codex"]),"first real mushroom gathering supplies one shared relationship proof")
	w.advance(float(w.relationships.config.check_interval)+.1) # Observe first actual commit through original system check cadence.
	w.advance(w.days.day_seconds+1.)
	check(BBQ.meal(w,"single:mushroom",["human","codex"]),"second genuine day meal earns second bounded shared proof without backfill")
	w.advance(float(w.relationships.config.check_interval)+.1) # Observe second actual commit through original cadence; never write counts.
	var r:RefCounted=w.director.routines.codex
	check(w.relationships.states.get("codex",{}).get("counts",{}).get("shared_barbecue",0)==2,"only two physically eaten distinct-day barbecues reach common-activity topic")
	var side_lines:Array=w.relationships.lines("codex","ambient")
	check(side_lines.size()==4,"actual shared relationship has original four authored aside lines")
	r.enabled=true;r.chatter=true;r.next_decision=INF;r.next_speech=0.;w.director.speech_after=0.
	for repeat in range(2):
		if repeat==1:
			check(side_lines.all(func(line):return not w.personality.allowed_line("codex",line)),"same-day authored lines do not repeat under current daily rule")
			r.enabled=false
			var previous_day:int=w.days.day()
			while w.days.day()==previous_day:w.advance(.5)
			r.enabled=true
		for line in side_lines:
			wait_speech_gate(w,r)
			check(w.director.say_local("codex",line,"ambient",w.personality.config.personal_gap,w.personality.config.village_gap),"real original speech outlet delivers each relationship line only within its retained repeat allowance")
	wait_speech_gate(w,r)
	check(w.personality.selection("codex",side_lines,r.recent_lines).is_empty(),"all four relationship asides genuinely reach their unchanged two-per-hour limit")
	var mood:String=w.director.moods.summary("codex").id
	var authored:Array=w.personality.pool("codex",mood if mood!="calm" else "ambient")
	var serial:int=w.director.serial;var actors:Dictionary=w.actors.duplicate(true)
	r._speak("ambient")
	check(w.director.serial==serial+1 and w.director.events[-1].text in authored and w.director.events[-1].text not in side_lines,"exhausted relationship aside falls back to an existing personality or mood line through original outlet")
	check(w.actors==actors and w.work.jobs.is_empty(),"personality fallback cannot move human or create work")
	# Speech-history boundary fixture only: never installed in a save or represented as a real meal.
	# Mark the remaining authored candidates at their same original maximum without changing config.
	for line in authored:
		while w.personality.allowed_line("codex",line):w.personality.note_line("codex",line)
	wait_speech_gate(w,r);serial=w.director.serial
	var state:int=r.rng.state;r._speak("ambient")
	check(w.director.serial==serial and r.rng.state==state,"when both original repeat-filtered pools are empty nothing is delivered and no selection RNG is consumed")
