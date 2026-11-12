extends SceneTree
func _initialize()->void:
	var w:=preload("res://scripts/world_state.gd").new();w.residents.provision(w)
	var r:RefCounted=w.director.routines.codex
	r.rng.seed=1027
	var state:int=r.decision_rng.state
	var actors:Dictionary=w.actors.duplicate(true)
	var routes:Dictionary=w._routes.duplicate(true)
	r._speak("ambient",true)
	assert(r.decision_rng.state==state,"speech cannot draw from the movement RNG")
	assert(w.actors==actors and w._routes==routes,"speech changes no actor position or route")
	var expected:=RandomNumberGenerator.new();expected.state=state
	assert(r.decision_rng.randi()==expected.randi(),"next decision draw is unchanged after speech")
	r.rng.seed=42
	var reset:=RandomNumberGenerator.new();reset.seed=42
	assert(r.decision_rng.randi()==reset.randi(),"explicit public reseed resets the independent decision stream")
	print("Speech RNG isolation: 4 checks")
	quit()
