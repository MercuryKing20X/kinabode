extends SceneTree
const W=preload("res://scripts/world_state.gd")
const S=preload("res://scripts/save_store.gd")
func _initialize()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"))
	var w:=W.new();w.residents.provision(w);w.director.set_all_enabled(false)
	w.actors.human.carry={"seed.pumpkin":1};w.actors.codex.carry={"tomato":3,"seed.tomato":1}
	assert(S.save_world(w,directory));assert(S.load_world(w,directory).ok)
	assert(not w.loaded("human") and not w.loaded("codex"));assert(int(w.actors.codex.carry.tomato)==3 and int(w.actors.codex.carry["seed.tomato"])==1)
	w.actors.human.erase("pocketed");w.actors.human.carry={"wood":19,"seed.pumpkin":1};w.advance(.1)
	assert(not w.actors.human.get("pocketed",false) and not w.pocket_notice.is_empty() and w.life.item_count(w.actors.human.carry)==20)
	w.actors.human.carry.wood=18;w.advance(.1);assert(w.actors.human.pocketed and w.life.item_count(w.actors.human.carry)==19 and w.loaded("human"))
	w.actors.human.carry={"seed.pumpkin":1};w.actors.human.erase("pocketed");w.work.jobs.human={"intent":"test"};w.auto_stow_idle();assert(not w.actors.human.get("pocketed",false));w.work.jobs.clear();w.advance(.1);assert(not w.loaded("human"))
	print("Auto pockets: old load/each resident, conservation, full20 notice, retry19, active work and wood gates passed");quit()
