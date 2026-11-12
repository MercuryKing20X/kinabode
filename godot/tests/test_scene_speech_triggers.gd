extends "res://tests/test_intelligence_core_input.gd"
var results:Dictionary={}
func advance(seconds:float)->void:
	for i in int(seconds*10):
		game._process(.1)
		if i%100==0:await process_frame
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	await advance(1)
	var s:RefCounted=w.scene_speech
	# Content contract: all 36 connected contexts have 4/6/4/4 unique, translated lines.
	var total:=0;var ids:Dictionary={}
	for scene in s.data.scenes:
		for tag in s.data.scenes[scene]:
			var rows:Array=s.data.scenes[scene][tag];check(rows.size()>=4 and rows.size()<=6,scene+" "+tag+" count")
			for row in rows:
				check(not ids.has(row.id) and not row.zh.is_empty() and not row.en.is_empty(),row.id+" paired unique")
				ids[row.id]=true;total+=1
	check(total>=400,"400+ paired lines")
	# These are state fixtures, not claims of native movement/weather UI acceptance.
	var id:String="codex";var original:Dictionary=w.actors[id].duplicate(true)
	var human:Dictionary=w.actors.human
	var hp:Vector2=w.point(human)
	w.actors[id].position=[hp.x+1,hp.y]
	s.still=35;s.near_seconds[id]=12
	check("idle" in s.contexts(id),"real stationary timer candidate")
	check("quiet_company" in s.contexts(id),"nearby silent timer candidate")
	for phase in ["morning","afternoon","dusk","night"]:
		var entry:Dictionary=w.days.config.phases.filter(func(p):return p.id==phase)[0]
		w.forest.clock=w.days.origin+w.days.day_seconds*float(entry.start)+1
		s.first_seen.clear();s.phase_seen.clear()
		var expected:String={"morning":"morning","afternoon":"noon","dusk":"dusk","night":"night"}[phase]
		check(expected in s.contexts(id),"real DayCycle "+expected)
	# Exact outlet & dedupe test: no direct state injection into speech history.
	for scene in s.data.scenes:
		var row:Dictionary=s.data.scenes[scene][w.personality.tag(id)][0]
		var text:String=row.zh
		w.director.routines[id].next_speech=w.director.routines[id].time
		w.director.speech_after=w.director.time
		var delivered:bool=w.director.say_local(id,text,"scene_fixture_"+scene,10,10)
		results[scene]=delivered
		check(delivered,scene+" original outlet (explicit fixture, not trigger proof)")
		check(not w.director.say_local(id,text,"scene_fixture_"+scene,10,10),scene+" original repeat/cooldown rejection")
	w.actors[id]=original
	# Stop gates remain authoritative in actual idle integration.
	w.director.routines[id].held=true
	check(not w.director.can_say_local(id),"held rejects new scene output")
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("triggers.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"fixture_outlet":results,"checks":checks,"failed":failed},"  "));f.close()
	game.queue_free();await process_frame
	print("SCENE_TRIGGERS ",checks," failed=",failed);quit(1 if failed else 0)
