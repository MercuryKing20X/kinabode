# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
## Integration — production/evidence/barbecue-v4 — BLOCKING station binding / conservation.
const H=preload("res://tests/test_barbecue_v2.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));var h:=H.new();var w:RefCounted=h.fresh(dir)
	for station_id in ["home.barbecue","moon.barbecue"]:
		var camp:RefCounted=w.barbecues[station_id]
		check(camp.fireside.invite([]).ok,"real configured circular seats available for radius regression "+station_id)
		var center:Vector2=w.point(camp.station);var sample:=Vector2.INF
		for index in range(64):
			var candidate:Vector2=center+Vector2.from_angle(index*TAU/64)*9
			if w.walkable(camp.station.region_id,candidate) and camp.seats().any(func(seat):return candidate.distance_to(w.point(seat))<=8):sample=candidate;break
		check(sample.is_finite() and F.job(w,"codex",{"intent":"move","x":sample.x,"y":sample.y}),"actor really walks nine cells from selected center "+station_id)
		var nearby:Array=w.nearby_camp_seats("codex",8)
		check(w.point(w.actors.codex).distance_to(center)>8 and nearby.any(func(seat):return str(seat.id).begins_with(station_id+".seat.")),"near-side seat inside original eight-cell reach is retained beyond center radius "+station_id)
		check(nearby.all(func(seat):return w.point(w.actors.codex).distance_to(w.point(seat))<=8),"far-side and other out-of-range seats excluded by true actor-to-seat distance "+station_id)
		var host_before:Dictionary=w.actors.human.duplicate(true);var material_before:Dictionary=camp.fireside.available().duplicate(true)
		check(w.director.routines.codex._start("rest") and F.wait(w,"codex"),"original local rest actually accepts near-side seat without controlling host "+station_id)
		for tick in range(3000):
			w.advance(.1)
			if not w._routes.has("codex"):break
		check(nearby.any(func(seat):return w.point(w.actors.codex).distance_to(w.point(seat))<.01) and w.actors.human==host_before and camp.fireside.available()==material_before and w.work.jobs.is_empty(),"actual local rest reaches a legal seat and changes no human or material "+station_id)
		w.director.routines.codex.interrupt(8)
	var records_before:int=w.memories.records.size()
	for station_id in ["moon.barbecue","home.barbecue"]:
		var life:RefCounted=w.barbecues[station_id];var other:RefCounted=w.barbecues["home.barbecue" if station_id=="moon.barbecue" else "moon.barbecue"]
		var human:Dictionary=w.actors.human.duplicate(true)
		check(life.fireside.invite(["codex","companion-2"]).ok,"host explicitly chooses exact camp "+station_id)
		w.advance(.2);check(w.actors.human==human,"invitation never moves human "+station_id)
		check(BBQ.approach(w,station_id),"real host route reaches exact camp across island geometry "+station_id)
		check(life.fireside.invite(["codex","companion-2"]).ok,"host reaffirms selected diners after actual long walk "+station_id)
		var other_state:Dictionary=other.station.duplicate(true);var wood:int=F.amount(w,"wood");var food:int=F.amount(w,"mushroom")
		check(life.fireside.light_host().ok and life.station.fuel_used==2,"selected camp consumes actual two wood "+station_id)
		check(F.amount(w,"wood")==wood-2 and other.station==other_state,"only exact selected station state changes on lighting "+station_id)
		check(life.fireside.roast_host("single:mushroom").ok and F.amount(w,"mushroom")==food,"unlimited mushrooms debit zero ingredients on selected camp "+station_id)
		check(other.station==other_state,"roasting cannot mutate another camp "+station_id)
		check(BBQ.ate(w,"human",station_id) and BBQ.ate(w,"codex",station_id) and BBQ.ate(w,"companion-2",station_id),"actual selected diners physically arrive and finish "+station_id)
		var cur:Dictionary=life.fireside.state.current
		check(cur.eaten==3 and cur.wasted==0 and life.station.portions==0 and cur.receipt.is_empty(),"per-camp output counts exactly three with empty debit "+station_id)
		life.fireside.end_circle("host ends actual selected camp")
		check(w.work.jobs.is_empty() and w.work.claims.is_empty(),"exact station releases its real claims "+station_id)
		var facts:Array=w.memories.records.filter(func(e):return e.kind=="shared_barbecue" and e.facts.station_id==station_id)
		check(facts.size()==1 and facts[0].participants==["codex","companion-2","human"] and facts[0].facts.place_id==life.station.get("place_id","home"),"canonical event has actual location and participants "+station_id)
		check(w.read_memories("npc.mira",{"kind":"shared_barbecue"}).total==0,"bystanders gain no invented shared experience "+station_id)
	check(w.memories.records.filter(func(e):return e.kind=="shared_barbecue").size()==2 and w.memories.records.size()>=records_before+2,"two distinct real gatherings retained")
	var raw_wood:int=F.amount(w,"wood");var raw_food:int=F.amount(w,"mushroom")
	check(Save.save_world(w,dir.path_join("both")),"save independent exact station receipts")
	var restored:RefCounted=h.fresh(dir.path_join("read"));check(Save.load_world(restored,dir.path_join("both")).ok,"reload both real camp states")
	check(restored.work.jobs.is_empty() and restored.work.claims.is_empty() and restored._routes.is_empty(),"reload never restores either station job route or claim")
	check(F.amount(restored,"wood")==raw_wood and F.amount(restored,"mushroom")==raw_food and restored.barbecues.values().all(func(l):return l.station.portions==0),"reload preserves raw items and produces no leftovers")
	for station_id in ["home.barbecue","moon.barbecue"]:
		check(restored.barbecues[station_id].station.fuel_used==2 and restored.barbecues[station_id].station.meals_eaten==3,"station counters never merge or replay "+station_id)
	var path:String=dir.path_join("both/island-v2.json");var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));data.extra_barbecues["moon.barbecue"].station.place_id="invented-place"
	preload("res://tests/fishing_fixture.gd").write_json(dir.path_join("invalid/island-v2.json"),data)
	var invalid:Dictionary=Save.load_world(h.fresh(dir.path_join("invalid-art")),dir.path_join("invalid"))
	check(not invalid.ok and FileAccess.file_exists(invalid.get("backup","")),"forged extra-camp location rejected with recoverable original")
	h.free();print("Multiple barbecues v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
