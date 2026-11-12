extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Motion=preload("res://scripts/actor_motion.gd")
const Data=preload("res://scripts/intelligence_catalog.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=World.new();w.residents.provision(w);w.intelligence.activate_presets();w.director.set_all_enabled(false)
	var motion:=Motion.new();var bobs:Dictionary={};var moving_frames:=0
	for id in w.actors:
		var gait:Dictionary=w.intelligence.gait(id)
		check(Data.valid_gait(gait),"strict authored gait available for "+id)
		var bad:Dictionary=gait.duplicate();bad["speed"]=999;check(not Data.valid_gait(bad),"gait cannot introduce gameplay speed")
		bad=gait.duplicate();bad.bounce=100;check(not Data.valid_gait(bad),"out-of-budget visual amplitude rejected")
		var initial:Dictionary=w.actors[id].duplicate(true);var p:Vector2=w.point(w.actors[id])
		check(w.command(id,{"intent":"move","x":p.x+3,"y":p.y}).ok,"real movement for gait "+id)
		bobs[id]=0.0
		# Avoid sampling human's 6px half-step at exactly 25Hz: that aliases
		# every bob sample onto sin(n*PI)==0 despite a nonzero authored gait.
		for frame in range(180):
			w.advance(.037)
			var running:Dictionary={};var movements:Dictionary={};var gaits:Dictionary={}
			for actor_id in w.actors:running[actor_id]=w.is_running(actor_id);movements[actor_id]=w.motion_state(actor_id);gaits[actor_id]=w.intelligence.gait(actor_id)
			motion.advance(.037,w.actors,running,movements,gaits)
			if not movements[id].moving:break
			moving_frames+=1
			var before:Dictionary=w.actors[id].duplicate(true);var pose:Dictionary=motion.pose(w.actors[id],{},w.actors,{"motion":movements[id],"gait":gait,"hunger":-1})
			bobs[id]=maxf(float(bobs[id]),absf(pose.bob))
			check(w.actors[id]==before,"presentation leaves real actor/carry/facing unchanged")
			var full:Dictionary=motion.pose(w.actors[id],{},w.actors,{"motion":movements[id],"gait":gait,"hunger":0})
			var hungry:Dictionary=motion.pose(w.actors[id],{},w.actors,{"motion":movements[id],"gait":gait,"hunger":2})
			check(absf(full.bob)>=absf(hungry.bob) and hungry.scale.y<1.05,"full gait is lively and hungry gait droops without speed changes")
		check(w.actors[id].carry==initial.carry,"gait never changes physical materials")
	check(float(bobs["companion-2"])>float(bobs.human) and float(bobs.human)>float(bobs.codex),"blue bounce exceeds natural human and white tiny-step amplitude")
	check(w.intelligence.gait("codex").step_scale>w.intelligence.gait("npc.mira").step_scale,"white tiny steps have faster authored cadence than orange broad stride")
	var copy:Dictionary=w.intelligence.gait("codex");copy.bounce=99
	check(w.intelligence.gait("codex").bounce!=99,"gait readers cannot mutate authored content")
	for id in ["companion-2","npc.nora"]:
		motion.states[id].phase=0
		var period:float=w.intelligence.gait(id).spin_every if id=="companion-2" else w.intelligence.gait(id).look_every
		var delta:float=period-fposmod(motion.time,period)+.1;w.advance(delta);motion.advance(delta,w.actors)
		var before:Dictionary=w.actors[id].duplicate(true)
		var pose:Dictionary=motion.pose(w.actors[id],{},w.actors,{"motion":w.motion_state(id),"gait":w.intelligence.gait(id),"routine_kind":"wander"})
		check(pose.get("idle_spin",false) if id=="companion-2" else pose.get("idle_glance",false),"authored idle-only spin/glance uses existing directional frames")
		check(w.actors[id]==before,"idle visual turn does not turn the simulation or move a body")
		pose=motion.pose(w.actors[id],{},w.actors,{"motion":{"moving":true,"facing":"left","still_seconds":0.0},"gait":w.intelligence.gait(id),"routine_kind":"wander"})
		check(not pose.get("idle_spin",false) and not pose.get("idle_glance",false) and pose.frame.begins_with("left_"),"moving hard rule always wins over playful idle gestures")
	print("Gait v4: ",checks," checks, failed=",failed,"; actual moving frames=",moving_frames,"; amplitudes=",bobs);quit(1 if failed else 0)
