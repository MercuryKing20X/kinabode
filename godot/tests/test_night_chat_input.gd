extends "res://tests/probe_first_hour.gd"
func show_state(when:String)->void:
	var fire:RefCounted=w.life.fireside
	var positions:Dictionary={}
	for id in ["human"]+IDS:positions[id]={"activity":w.actors[id].activity,"seated":fire.jobs.has(id),"held":w.activities.held.get(id,false),"can_say":w.director.can_say_local(id,"company_night")}
	print("NIGHT_DIAGNOSTIC ",JSON.stringify({"when":when,"phase":w.days.phase().id,"available":c.night.available_fire(),"burning":fire.burning(),"closed":fire.circle_closed,"positions":positions,"status":g.status.text}))

func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(2);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	await prepare_scene(directory,false)
	calm()
	w.days.origin=w.forest.clock-w.days.day_seconds*.64
	check(Cook.start(w,"single:mushroom",["human","codex","companion-2","npc.mira","npc.nora"]).ok and Cook.ready(w) and Cook.ate(w,"human") and Cook.ate(w,"codex"),"real meal receipt")
	w.director.speech_after=0
	for id in IDS:w.director.routines[id].next_speech=0
	show_state("before")
	await send("讲个故事吧")
	show_state("after_input")
	check(c.night.scene.get("kind","")=="story","typed input starts scene through Main")
	await tick_for(8)
	check(c.trace.any(func(e):return e.kind=="night_line"),"at least one spoken story line")
	g.queue_free();await frames();quit(1 if failures else 0)
