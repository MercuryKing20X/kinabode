extends "res://tests/test_brain_contract.gd"
func run()->void:
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	preload("res://scripts/world_opening.gd").apply(w,w.library,"standard");w.intelligence.activate_presets();w.hunger.start()
	var original:Dictionary=w.storage.saved().duplicate(true)
	var b:RefCounted=w.director.brains.codex
	var c:RefCounted=w.director.brains["companion-2"]
	for scene in b.interactions.data.scenes.values():
		for voice in scene.voices.values():check(voice.zh.size()>=5 and voice.en.size()>=5,"authored bilingual scene minimum")
	check(not b.interactions.social("chop").ok and b.refusal.is_empty(),"labor cannot enter social refusal policy")
	check(not b.interactions.social("roast").ok and b.refusal.is_empty(),"meal cannot enter social refusal policy")
	check(not b.interactions.social("assemble").ok and b.refusal.is_empty(),"assembly cannot enter social refusal policy")
	w.activities.set_followers([])
	var anchor:Vector2=w.point(w.actors["companion-2"])
	check(w.host_command("codex",{"intent":"move","x":anchor.x+1.5,"y":anchor.y}).ok,"pair approaches through actual World route")
	for tick in 1200:
		w.advance(.1)
		if not w._routes.has("codex"):break
	check(w.point(w.actors.codex).distance_to(anchor)<3,"real pair approach arrives")
	# The human leaves by an explicit host route; no resident moves the human.
	var host:Vector2=w.point(w.actors.human)
	var moved:bool=false
	for offset in [Vector2(22,0),Vector2(0,22),Vector2(-22,0)]:
		if w.host_command("human",{"intent":"move","x":anchor.x+offset.x,"y":anchor.y+offset.y}).ok:moved=true;break
	check(moved,"host explicitly walks away from the pair")
	for tick in 2000:
		w.advance(.1)
		if not w._routes.has("human"):break
	w.director.set_all_enabled(true)
	var accepted:=false
	for attempt in 20:
		if b.invite("companion-2","pair_sweep"):accepted=true;break
	check(accepted,"two residents agree without host presence")
	b.start({"action":"pair_sweep","score":1000,"reasons":["social"],"partner":"companion-2"},[])
	var simultaneous:=false;var absent:=false
	for tick in 400:
		w.advance(.1)
		if b.current.get("paired",false) and c.current.get("paired",false) and not w._routes.has("codex") and not w._routes.has("companion-2") and w.point(w.actors.codex).distance_to(w.point(w.actors["companion-2"]))<=4:
			simultaneous=true
			if b.distance()>12 and c.distance()>12:absent=true
	check(simultaneous,"accepted peers really arrive and share the same action")
	print("PAIR_FINAL ",w.point(w.actors.human)," ",w.point(w.actors.codex)," ",w.point(w.actors["companion-2"])," simultaneous=",simultaneous," absent=",absent)
	check(absent,"shared activity works while human is absent")
	check(b.interactions.receipts.any(func(row):return row.listener=="companion-2") or c.interactions.receipts.any(func(row):return row.listener=="codex"),"shared activity has delivered peer dialogue")
	check(b.interactions.receipts.any(func(row):return row.event=="peer_comment") or c.interactions.receipts.any(func(row):return row.event=="peer_comment"),"peers really comment while doing the shared activity")
	check(w.storage.saved()==original and w.work.jobs.is_empty(),"cosmetic shared play produces no labor or resources")
	print("BRAIN_SOCIAL ",checks," failed=",failed);quit(1 if failed else 0)
