extends SceneTree
## Actual five-diner meal: scene content, shared meal/day repetition and retained gates.
const Fixture=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var helper:=Fixture.new()
	var w:RefCounted=helper.fresh(OS.get_environment("HABITAT_DATA_DIR"))
	w.world_id="00000000-0000-4000-8000-000000006101"
	w.intelligence.activate_presets()
	var f:RefCounted=w.life.fireside
	check(helper.pickup(w,"wood",4) and helper.approach(w,w.life),"host brings actual initial wood by World route")
	check(f.light_host().ok and f.light_host().ok and f.invite(["codex","companion-2","npc.mira","npc.nora"]).ok,"host lights and explicitly invites four diners")
	w.director.set_all_enabled(true)
	check(f.roast_host("single:turnip").ok,"real initial turnips pay for five actual meals")
	var record:Array=[];var serial:int=w.director.serial
	var texts:Dictionary={};var contexts:Dictionary={}
	for frame in range(650):
		w.advance(.1)
		for e in w.director.events:
			if e.serial<=serial:continue
			serial=e.serial
			if not str(e.context).begins_with("fireside_"):continue
			check(not texts.has(e.text),"same gathering never delivers the same text twice")
			var context:String=f.dialogue.last_context.get(w.world_id+":"+e.actor_id,"")
			check(contexts.get(e.actor_id,"")!=context,"a resident changes canonical scene between delivered lines")
			check(e.source=="local_rules" and e.actor_id in f.state.attended,"speech follows a real seated resident through original outlet")
			texts[e.text]=true;contexts[e.actor_id]=context
			record.append({"time":e.time,"actor":e.actor_id,"scene":context,"text":e.text})
		if f.circle_closed:break
	check(f.state.current.eaten==5 and f.circle_closed,"actual five-person meal finishes and timed circle ends")
	check(record.size()>=4,"complete real meal has audible authored dialogue")
	var d:RefCounted=f.dialogue
	var delivered_days:Dictionary=d.delivered_days.get(d.speech_key(),{})
	for id in delivered_days:
		for text in delivered_days[id]:
			check(not d.fresh_line(id,text,"different_scene"),"same resident cannot repeat an actual delivered line on the same day")
	var first_meal:String=d.meal_key()
	check(f.light_host().ok and f.invite(["codex"]).ok and f.roast_host("single:mushroom").ok,"host starts another actual batch after previous circle")
	check(d.meal_key()!=first_meal,"gathering identity changes only for a new committed circle")
	# Same gathering can contain multiple cooked batches; all use the gathering ID.
	var next_meal:String=d.meal_key()
	for frame in range(180):
		w.advance(.1)
		if f.state.current.eaten==2:break
	check(f.roast_host("single:mushroom").ok and d.meal_key()==next_meal,"another cooked batch does not reset same-gathering deduplication")
	var out:String=OS.get_environment("HABITAT_BBQ_SCENES_EVIDENCE")
	if not out.is_empty():FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"meal":record,"eaten":5,"checks":checks,"failed":failed},"  "))
	f.end_circle("explicit QA end");helper.free()
	print("Barbecue authored scenes: ",checks," checks, failed=",failed);quit(1 if failed else 0)
