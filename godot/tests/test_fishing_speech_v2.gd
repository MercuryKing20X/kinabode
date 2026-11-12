extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var world:=preload("res://scripts/world_state.gd").new();world.residents.provision(world);world.intelligence.activate_presets()
	var traits:Array=["gentle","curious","curious-context","slow-warm","lively","glutton","glutton-minor","clingy","laborious","serious","quiet","introvert","night-owl"]
	var contexts:Array=["invited","cast","wait","bite","small","large","rare","lost","witness","first","stock","release"]
	var font:Font=load("res://assets/fonts/NotoSansSC.ttf")
	for trait_id in traits:
		for context in contexts:
			var uid:String="fish-v2-"+trait_id+"-"+context
			var unit:Dictionary=world.intelligence.catalog.speech.get(uid,{})
			check(world.intelligence.catalog.traits[trait_id].speech_units.has(uid) and unit.get("context")=="fishing_v2_"+context and unit.get("lines",[]).size()==4 and not unit.get("autonomy_output",true),"four authored local lines for "+trait_id+" "+context)
			for line in unit.get("lines",[]):
				for i in range(line.length()):
					var code:int=line.unicode_at(i)
					if code>32 and not font.has_char(code):check(false,"font missing "+String.chr(code)+" "+uid)
	for id in ["codex","companion-2","npc.mira","npc.nora"]:
		for context in contexts:
			var expected:String="fish-v2-"+world.intelligence.tag(id)+"-"+context
			check(world.intelligence.speech_pool(id,"fishing_v2_"+context)==world.intelligence.catalog.speech[expected].lines,"active personality selects correct pool "+id+" "+context)
	var life:RefCounted=world.fishing.life
	check(life.catch_context({"color_id":"cream","scale":1.0},false)=="small","small actual fish selects small event")
	check(life.catch_context({"color_id":"cream","scale":7.0},false)=="large","giant actual fish selects large event")
	check(life.catch_context({"color_id":"aurora","scale":1.0},false)=="rare","rare color selects rare event")
	check(life.catch_context({"color_id":"aurora","scale":7.0},true)=="first","actual first discovery has explicit priority")
	var actor:String="codex";var before:int=world.director.serial
	world.director.routines[actor].set_chatter(false)
	check(not world.fishing.life._line(actor,"wait") and world.director.serial==before,"chatter off blocks fishing speech")
	world.director.routines[actor].set_chatter(true);world.director.routines[actor].set_held(true)
	check(not world.fishing.life._line(actor,"bite") and world.director.serial==before,"held blocks fishing speech")
	world.director.routines[actor].set_held(false);world.fishing.life.cancel(actor,"stop")
	check(not world.fishing.life._line(actor,"cast") and world.director.serial==before,"stop quiet period blocks fishing speech")
	# Observe replies only after a real, independently caught fish exists.
	var probe:=preload("res://scripts/world_state.gd").new();probe.residents.provision(probe);probe.intelligence.activate_presets();probe.director.set_all_enabled(true);probe.fishing.rng.seed=101
	check(preload("res://tests/fishing_fixture.gd").coast(probe,"human"),"actual World route reaches shore for reply check")
	var invited:Dictionary=probe.fishing.invite_host(["codex","companion-2"])
	check(invited.accepted.size()==2,"two real independent fishers invited")
	var observed:Dictionary={};var one_per_catch:=true
	for tick in range(1600):
		probe.advance(.1)
		var per_fish:Dictionary={}
		for reply in probe.fishing.life.replies:
			per_fish[reply.fish_id]=int(per_fish.get(reply.fish_id,0))+1;observed[reply.fish_id]=true
		if per_fish.values().any(func(n):return n>1):one_per_catch=false
		if not observed.is_empty():break
	check(not observed.is_empty() and one_per_catch,"one real caught fish schedules at most one neighbour reply")
	print("Fishing personality speech v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)
