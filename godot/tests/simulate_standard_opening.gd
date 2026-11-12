extends SceneTree
const Fixture=preload("res://tests/standard_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");var output:=OS.get_environment("HABITAT_STANDARD_EVIDENCE");assert(dir.contains("youqi-test-") and not output.is_empty())
	var f:=Fixture.new();f.start(dir.path_join("first"))
	if not f.build_first() or not f.shared_meal():quit(1);return
	f.advance(180)
	var first_event:Dictionary=f.timeline.filter(func(e):return e.event=="first_meal_finished")[0]
	while f.elapsed<3600:f.tick(.5)
	f.check(f.w.memories.records.filter(func(e):return e.kind=="first_shared_meal").size()==1,"first memory is once-only")
	f.check(f.wood_audit().conserved,"first meal wood conserved")
	f.check(f.food_audit().conserved,"first meal crops and all real mushrooms conserved")
	f.check(f.w.standard.spoken.size()==4,"all four authored reactions delivered through original gaps")
	f.check(Save.save_world(f.w,dir.path_join("first-save")),"real first meal saves")
	f.check(f.w.standard.config.companions.all(func(id):return f.w.relationships.states.get(id,{}).get("counts",{}).get("shared_barbecue",0)==1),"each real participant gets original bounded barbecue credit once")
	var neglect:=Fixture.new();neglect.start(dir.path_join("neglect"))
	while neglect.elapsed<1800:
		var trees:Array=neglect.w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and o.zone_id=="home.forest")
		if trees.is_empty():neglect.tick();continue
		var r:Dictionary=neglect.w.command("human",{"intent":"gather_wood","zone_id":trees[0].zone_id,"target_id":trees[0].id,"tree_count":1})
		if not r.ok:neglect.advance(10);continue
		while neglect.elapsed<1800 and (neglect.w.work.jobs.has("human") or neglect.w._routes.has("human")):neglect.tick()
	neglect.check(neglect.w.standard.config.companions.all(func(id):return neglect.w.hunger.rank(id)==3),"neglect makes every companion very hungry")
	neglect.check(neglect.w.standard.config.companions.all(func(id):return not neglect.w.work.jobs.has(id) and (neglect.w.hunger.follow_targets.has(id) or neglect.w.point(neglect.w.actors[id]).distance_to(neglect.w.point(neglect.w.actors.human))<=2)),"hungry companions follow without doing work")
	neglect.check(neglect.wood_audit().conserved,"neglect preserves every real material")
	neglect.check(neglect.food_audit().conserved,"neglect never consumes any real food")
	# Continue the real opening for three DayCycle days; farm food replaces finite mushrooms.
	var three:=Fixture.new();three.start(dir.path_join("three"));three.audit_sources=true;if not three.build_first() or not three.shared_meal():quit(1);return
	var crops:Array=three.w.farms.farm_plots("farm.home").slice(0,4)
	for plot in crops:
		three.job({"intent":"plant","target_id":plot.id,"crop_id":"turnip"});three.job({"intent":"water","target_id":plot.id})
	var plot:Dictionary=crops[0]
	var reachable:=[true];var next_food:float=three.elapsed+400
	while three.elapsed<4500:
		if three.elapsed>=next_food:
			next_food=three.elapsed+600
			var w:RefCounted=three.w
			for field in crops:
				if w.farms.stage(field)!="mature":continue
				three.job({"intent":"harvest","target_id":field.id});three.job({"intent":"plant","target_id":field.id,"crop_id":"turnip"});three.job({"intent":"water","target_id":field.id})
			if w.life.station.state=="cold":
				var guests:Array=["codex","companion-2"] if int(three.elapsed/600)%2==0 else ["npc.mira","npc.nora"]
				preload("res://tests/barbecue_fixture.gd").meal(w,"recipe:turnip-soup",["human"]+guests,"home.barbecue",three.tick)
			var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature")
			var wood_path:bool=trees.any(func(tree):return not w.approach_route("human",tree).is_empty())
			var food_path:bool=not w.approach_route("human",{"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}).is_empty() and not w.approach_route("human",plot).is_empty()
			var renewable:bool=not plot.crop_id.is_empty() and plot.watered
			if not (wood_path and food_path and renewable):print("SOURCE AUDIT ",three.elapsed," wood=",wood_path," food=",food_path," growing=",renewable," ",plot)
			reachable.append(wood_path and food_path and renewable)
		three.tick()
	three.check(three.interruptions.is_empty(),"three-day no unexplained real task interruption")
	three.check(three.wood_audit().conserved,"three-day physical wood conserved")
	three.check(three.food_audit().conserved,"three-day crops, mushrooms, cooking buffers all conserved")
	three.check(reachable.all(func(ok):return ok),"wood and growing food routes remain available at each audit")
	var data:Dictionary={"first_hour":{"elapsed":f.elapsed,"first_meal_seconds":first_event.seconds,"timeline":f.timeline,"wood":f.wood_audit(),"food":f.food_audit(),"relationships":f.w.relationships.saved(),"spoken":f.w.standard.spoken,"hunger_seconds":f.w.hunger.statistics.state_seconds,"checks":f.checks,"failed":f.failed},"neglect_30min":{"timeline":neglect.timeline,"wood":neglect.wood_audit(),"food":neglect.food_audit(),"hunger_seconds":neglect.w.hunger.statistics.state_seconds,"following":neglect.w.hunger.follow_targets.keys(),"checks":neglect.checks,"failed":neglect.failed},"three_days":{"elapsed":three.elapsed,"timeline":three.timeline,"wood":three.wood_audit(),"food":three.food_audit(),"interruptions":three.interruptions,"reachable":reachable,"source_audits":three.source_audits,"checks":three.checks,"failed":three.failed},"zero_model_calls":true}
	var file:=FileAccess.open(output.path_join("simulation.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
	print("Standard opening simulations: ",f.checks+neglect.checks+three.checks," checks, failed=",f.failed or neglect.failed or three.failed)
	quit(1 if f.failed or neglect.failed or three.failed else 0)
