extends SceneTree
const W=preload("res://scripts/world_state.gd")
const L=preload("res://scripts/character_library.gd")
func _initialize()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=W.new("res://content/home-v3/world.json");assert(w.error.is_empty(),w.error)
	w.residents.provision(w);w.director.set_all_enabled(false)
	var d:RefCounted=w.dark;var e:RefCounted=d.discoveries
	assert(d.config.areas.size()==6 and d.config.areas.filter(func(a):return a.has("beacon")).size()==4)
	assert(not d.config.areas.filter(func(a):return a.id=="stars")[0].has("beacon"))
	assert(e.config.objects.size()==12 and e.valid({}))
	assert(not e.valid({"found":["invented"]}) and not e.valid({"found":["bell","bell"]}))
	var state:Dictionary=d.saved();assert(d.valid(state,w.actors));state.discoveries.found=["bell"];assert(d.valid(state,w.actors))
	state.discoveries.found=["unknown"];assert(not d.valid(state,w.actors))
	var a:Dictionary=w.actors.codex;a.carry={"seed.pumpkin":1};assert(w.stow_loose("codex").ok and not w.loaded("codex"))
	assert(w.work.carry_space("codex")==19);a.carry.wood=1;assert(w.loaded("codex"))
	print("Dark round2: geometry, stars, strict discovered IDs, resident pocket conservation passed");quit()
