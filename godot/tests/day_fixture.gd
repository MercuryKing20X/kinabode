extends RefCounted
static func enable_idle(world: RefCounted,id: String="codex") -> void:
	# C: This helper isolates daily idle opportunities from default following.
	world.activities.default_follow_excluded[id]=true
	world.activities.release_follow(id)
	var routine: RefCounted=world.director.routines[id]
	routine.set_enabled(true);routine.set_chatter(true);routine.next_decision=1e12;routine.next_speech=0
	world.director.speech_after=0
static func advance_to(world: RefCounted,seconds: float) -> void:
	var remaining: float=seconds-(world.forest.clock-world.days.origin)
	if remaining>0:world.advance(remaining)
