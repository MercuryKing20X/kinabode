extends SceneTree
const W=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
func _initialize()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=W.new("res://content/home-v3/world.json");w.residents.provision(w);w.director.set_all_enabled(false)
	var d:RefCounted=w.dark;var e:RefCounted=d.discoveries
	w.actors.human.region_id="dark";w.actors.human.position=[42,79];d.torch.owned=true;d.torch.remaining=120
	assert(e.begin("bell",Vector2(42,79)).ok)
	for i in range(20):w.advance(.1)
	assert("bell" in e.found and w.memories.records.any(func(r):return r.kind=="dark_discovery"))
	for id in ["fly-7","fly-8","fly-9"]:
		var g:Array=d.config.glows[int(id.trim_prefix("fly-"))].position
		w.actors.human.position=g.duplicate();assert(e.begin(id,d.p(g)).ok)
		for i in range(20):w.advance(.1)
	assert(int(w.actors.human.carry.get("firefly.jar",0))==1 and e.loose==0)
	var g:Array=d.config.glows[9].position;assert(not e.begin("fly-9",d.p(g)).ok)
	w.actors.human.region_id="home";w.actors.human.position=[51,44];assert(e.place_jar().ok and e.lamps.size()==1)
	assert(e.reclaim_jar().ok and e.lamps.is_empty() and int(w.actors.human.carry.get("firefly.jar",0))==1)
	w.actors.human.region_id="dark";w.actors.human.position=e.config.star_seat.duplicate()
	assert(e.begin("stars",d.p(e.config.star_seat)).ok)
	for i in range(20):w.advance(.1)
	assert(e.star_days.size()==1);e.stop_stars();assert(e.begin("stars",d.p(e.config.star_seat)).ok)
	for i in range(20):w.advance(.1)
	assert(e.star_days.size()==1)
	assert(Save.save_world(w,OS.get_environment("HABITAT_DATA_DIR")));assert(Save.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).ok)
	assert("bell" in e.found and e.catches.size()==3 and e.star_days.size()==1)
	print("Discovery commit: real advance, relic memory, three catches/one jar, daily reject, place/reclaim, daily stars and reload passed");quit()
