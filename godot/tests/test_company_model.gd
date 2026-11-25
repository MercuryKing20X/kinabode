extends "res://tests/test_company_input.gd"

func attach(id:String)->void:
	g._ensure_link(id);w.director.set_controller(id,"model")
	g.resident_connections.preferences.choose(id,"lifeblood")
	g.resident_connections.preferences.enable_autonomy(id,true)
	g.autonomy.refresh_support()
func reply(id:String,payload:Dictionary)->bool:
	var key:String="company-stub-"+str(c.trace.size())
	var n:int=c.trace.filter(func(row):return row.kind=="model_written").size()
	if not g.autonomy.dispatch(id,{},{"tools":1},key):return false
	var link:Node=g.links[id]
	var captured:Dictionary=link.get_meta("test_context",{})
	var request:Dictionary=captured.get("heart_card",{}).get("company_request",{})
	if request.is_empty():return false
	g.autonomy.scheduler.active[id]={"id":key,"day":g.autonomy.scheduler.day_key(),"tokens":0,"input":0,"output":0,"reserve":0}
	if request.kind in ["story","question"]:
		check(g.autonomy.owns_turn(id),"native fixture owns the bound night request")
		g.autonomy.tick(.1)
		check(g.autonomy.owns_turn(id) and not link._cancelling,"seated night request survives the normal scheduler frame")
	link._accept_event({"kind":"intent_result","turn_key":key,"speech":"","company_reply":payload.merged({"id":request.id})})
	g.autonomy.scheduler.active.erase(id)
	link._accept_event({"kind":"state","state":"ready","turnComplete":true})
	return c.trace.filter(func(row):return row.kind=="model_written").size()==n+1
func run()->void:
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	if not base.contains("youqi-test-"):quit(2);return
	OS.set_environment("HABITAT_OPENING","showcase")
	await load_game(base.path_join("model"))
	for id in ["codex","companion-2"]:attach(id)
	calm();nearby("codex")
	check(g.links.codex is OfflineLink and g.links["companion-2"] is OfflineLink,"both adapters are stubs before the scene starts")
	check(c.start_care("codex","pat"),"care event authorized")
	step(.2)
	check(reply("codex",{"text":"轻一点呀，我在这里。"}),"bound stub writes only the care response")
	c.end_care();c.return_scene={"saved_wall":10000,"band":1,"absence_seconds":18000.0}
	c.welcome_letter("codex")
	check(reply("codex",{"text":"你回来了。今早的风轻轻的，等你有空再坐一会儿。"}),"real return event authorizes a stub letter")
	var letters:Array=g.memory_books.list_for("codex","letters")
	check(not letters.is_empty() and letters[-1].source=="ai" and g.memory_books.entries.has(letters[-1].params.source_ids[0]),"AI letter preserves actual source")
	calm();nearby("codex",3)
	var at:Vector2=w.point(w.actors.codex)
	c.return_scene={"state":"greeting","saved_wall":10001,"saved_day":1,"absence_seconds":18000.0,"band":1,
		"targets":{"codex":at},"routes":{"codex":[]},"arrived":[],"until":w.forest.clock+18,"next":w.forest.clock,"matured":0}
	w.activities.opening_party.append("codex")
	c.welcome_letter("codex")
	var greeting:="你到家了。我正好想陪你坐一下。"
	check(reply("codex",{"text":"岛主，你回来了。","greeting":greeting}),"valid reply binds the letter and greeting to the actual return")
	for index in 90:
		g._process(.2)
		if c.return_scene.state=="done":break
	var bubble:Dictionary=g.view.speech_by_actor.get("codex",{})
	check(bubble.get("source")=="model" and bubble.get("context")=="company_return" and bubble.get("text")==greeting,"arrived resident shows the model greeting in the viewport source")
	c.welcome_letter("companion-2")
	c.model_pending.erase("companion-2")
	c.return_scene.clear();calm();nearby("codex")
	check(c.night.offer("codex"),"promise prepared by host")
	check(reply("codex",{"choice":"social_fireside"}),"stub selects checked promise option")
	check(c.night.offered.action=="social_fireside" and w.promises.social("codex").is_empty(),"model selection never accepts for player")
	c.night.close_card();c.night.offered.clear()
	check(enter_fireside(),"grounded fireside fixture")
	w.director.speech_after=0
	for id in c.IDS:w.director.routines[id].next_speech=0
	check(c.night.start("story"),"story session established")
	var who:String=c.night.scene.get("id","")
	var binding:Dictionary=c.model_pending.get(who,{})
	if not binding.get("binding",{}).get("sources",[]).is_empty():
		check(reply(who,{"source_id":binding.binding.sources.back(),"lines":["你真的回来啦。","刚才听见柴火啪的一声。","这火边可以慢慢坐。"]}),"stub writes bounded story with actual source")
	else:check(false,"story has true referenced source")
	c.night.end_scene();w.days.origin-=w.days.day_seconds
	w.director.speech_after=0
	for id in c.IDS:w.director.routines[id].next_speech=0
	check(c.night.start("question"),"question session established")
	who=c.night.scene.get("id","")
	check(not who.is_empty() and reply(who,{"text":"下雨时你想听什么？","options":["听浪","听雨"]}),"stub authors question and exact local options")
	check(c.night.turn.get("choices",[])==["听浪","听雨"],"stub only changes question card")
	c.night.close_card();c.night.end_scene();Cook.end(w);calm();nearby("codex")
	for mode in ["no_reply","wrong_actor","stale_turn","malformed","unsupported","expired"]:
		c.model_pending.clear()
		var before:Dictionary=w.hearts.mood("codex")
		check(c.model_offer("codex","care",{},{"action":"pat","care_sequence":c.care_count.get("codex:pat",0)}),"fallback setup "+mode)
		var card:Dictionary=c.model_card("codex","bound")
		var payload:Variant={"id":card.get("id",""),"text":"我还在这里。"}
		var accepted:=false
		match mode:
			"no_reply":
				c.model_pending.codex.until=w.forest.clock-1;c.tick(.1)
				accepted=c.model_pending.has("codex")
			"wrong_actor":accepted=c.model_result("companion-2","bound",payload)
			"stale_turn":accepted=c.model_result("codex","old",payload)
			"malformed":accepted=c.model_result("codex","bound","broken JSON")
			"unsupported":
				payload.text="https://invalid.example";accepted=c.model_result("codex","bound",payload)
			"expired":
				c.model_pending.codex.until=w.forest.clock-1;accepted=c.model_result("codex","bound",payload)
		check(not accepted and w.hearts.mood("codex")==before,"fallback preserves local outcome "+mode)
	print("COMPANY_MODEL_FAILURES ",failures)
	g.queue_free();await frames();quit(1 if failures else 0)
