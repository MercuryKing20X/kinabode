extends SceneTree
const W=preload("res://scripts/world_state.gd")
const S=preload("res://scripts/save_store.gd")
func _initialize()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=W.new();w.residents.provision(w);w.director.set_all_enabled(false)
	w.actors.human.carry={"seed.pumpkin":1}
	assert(w.loaded("human"));assert(w.stow_loose().ok)
	assert(not w.loaded("human") and w.actors.human.carry.size()==1 and int(w.actors.human.carry.get("seed.pumpkin",0))==1 and w.work.carry_space("human")==19)
	w._apply_route("human",[w.point(w.actors.human)+Vector2(15,0)]);assert(w.is_running("human"))
	assert(S.save_world(w,OS.get_environment("HABITAT_DATA_DIR")));assert(S.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).ok)
	assert(not w.loaded("human") and w.actors.human.carry.size()==1 and int(w.actors.human.carry.get("seed.pumpkin",0))==1)
	w.actors.human.carry.wood=1;assert(w.loaded("human"))
	w.actors.human.carry={"seed.pumpkin":1,"wood":19};w.actors.human.erase("pocketed")
	assert(not w.stow_loose().ok and w.work.carry_space("human")==0 and w.actors.human.carry=={"seed.pumpkin":1,"wood":19})
	w.actors.human.carry={"seed.pumpkin":1};w.work.jobs.human={"intent":"test"}
	assert(not w.stow_loose().ok and w.loaded("human"));w.work.jobs.clear()
	w.actors.codex.carry={"seed.pumpkin":1};assert(w.loaded("codex"))
	print("Pocketed items: conservation, fixed20, save/load, work/wood/resident gates passed");quit()
