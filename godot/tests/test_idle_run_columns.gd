extends SceneTree
const W=preload("res://scripts/world_state.gd")
const Motion=preload("res://scripts/actor_motion.gd")
func _initialize()->void:
	var w:=W.new();w.residents.provision(w);w.director.set_all_enabled(false)
	var m:=Motion.new();var origin:Vector2=w.point(w.actors.human)
	w.actors.human.carry={"seed.pumpkin":1};w.auto_stow_idle();w._apply_route("human",[origin+Vector2(15,0)])
	var cols:Dictionary={};var frames:=0
	for i in range(240):
		if not w._routes.has("human"):break
		w.advance(1.0/60)
		m.advance(1.0/60,w.actors,{"human":w.display_running("human")},{"human":w.motion_state("human")},{"human":{}})
		if w.motion_state("human").moving:assert(w.display_running("human"));cols[m.run_column("human",{})]=true;frames+=1
	assert(frames>0 and cols.size()==6)
	print("Idle seed route: every movement runs and all six columns observed");quit()
