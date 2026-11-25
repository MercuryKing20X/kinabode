class_name ActorMotion
extends RefCounted

# Presentation only: never changes an actor, a route, inventory, or simulation time.
var states: Dictionary = {}
var play_poses:Dictionary={}
var play_phases:Dictionary={}
var time := 0.0
var attention_until := 0.0
const WORK_ACTIVITIES=["chopping","gathering","watering","picking_up","putting_down","building","fish_cast","fish_wait","fish_bite","fish_reel","planting","harvesting","delivering"]
const WORK_INTENTS=["chop","gather_wood","forage","fish","plant","water","harvest","build","build_house","deliver_wood","house_work","storage_delivery"]
static func working(actor:Dictionary,job:Dictionary)->bool:
	return actor.activity in WORK_ACTIVITIES or job.get("intent","") in WORK_INTENTS
# One six-frame walk cycle per this many real pixels, scaled by gait step_scale.
const WALK_STRIDE_PIXELS := 48.0
const GESTURE_DEFAULT={"version":1,"wave":{"duration":.7,"bounce_pixels":2.5,"lean":.025},"stretch":{"duration":1.2,"scale_x":.985,"scale_y":1.035}}
var gestures:Dictionary=GESTURE_DEFAULT.duplicate(true)
static func _gesture_number(value:Variant,low:float,high:float)->bool:
	return (value is int or value is float) and is_finite(value) and value>=low and value<=high
static func valid_gestures(value:Variant)->bool:
	if not value is Dictionary or value.size()!=3 or not value.has_all(["version","wave","stretch"]) or not _gesture_number(value.version,1,1):return false
	var wave:Variant=value.wave;var stretch:Variant=value.stretch
	if not wave is Dictionary or wave.size()!=3 or not wave.has_all(["duration","bounce_pixels","lean"]):return false
	if not stretch is Dictionary or stretch.size()!=3 or not stretch.has_all(["duration","scale_x","scale_y"]):return false
	return _gesture_number(wave.duration,.1,5) and _gesture_number(wave.bounce_pixels,0,10) and _gesture_number(wave.lean,0,.2) and _gesture_number(stretch.duration,.1,5) and _gesture_number(stretch.scale_x,.9,1) and _gesture_number(stretch.scale_y,1,1.2)
func _init()->void:
	var path:="res://content/gesture_motion.json"
	if FileAccess.file_exists(path):
		var configured:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if valid_gestures(configured):gestures=configured
		else:push_warning("Invalid gesture presentation; using defaults")

func attend() -> void:
	attention_until = time + 2.2

func advance(delta: float, actors: Dictionary, running: Dictionary = {}, movements:Dictionary={},gaits:Dictionary={}) -> void:
	time += delta
	for id in actors:
		if not states.has(id):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(id)
			states[id] = {"rng": rng, "phase": rng.randf_range(0, TAU), "blink_at": time + rng.randf_range(2, 6), "blink_until": 0.0, "step": 0.0, "activity": "idle", "activity_age": 0.0}
		var state: Dictionary = states[id]
		var activity: String = actors[id].activity
		if state.activity != activity: state["think_until"] = 0.0
		state.activity_age = float(state.activity_age) + delta if state.activity == activity else 0.0
		state.activity = activity
		var moving:bool=movements.get(id,{}).get("moving",activity=="walking")
		var now_running:bool=moving and bool(running.get(id,false))
		if now_running:
			state["run_route"]=true
			state["run_pixels"]=float(state.get("run_pixels",0))+float(movements.get(id,{}).get("distance",0))*32.0
		if now_running and not state.get("was_running",false):state["run_started"]=time
		if not moving and state.get("run_route",false):state["run_stopped"]=time;state["run_route"]=false
		state["was_running"]=now_running
		if now_running:
			# Six displayed columns per stride; all fallback poses share the same odometer.
			var gait:Dictionary=gaits.get(id,{})
			state.step=float(state.get("run_pixels",0))*float(gait.get("run_frames_per_step",gait.get("step_scale",1.0)))/96.0
		elif moving:
			# Walking also follows the real odometer so feet never slide when speed changes
			# (carry, hunger, follow). No movement evidence means no invented footsteps.
			var walked:Variant=movements.get(id,{}).get("distance",null)
			if walked==null:pass # No displacement evidence: do not animate planted feet.
			else:state.step += float(walked) * 32.0 * float(gaits.get(id,{}).get("step_scale",1.0)) / WALK_STRIDE_PIXELS
		else:state.step=0.0
		if time >= float(state.blink_at):
			state.blink_until = time + .14
			state.blink_at = time + state.rng.randf_range(3.1, 6.4) / float(gaits.get(id,{}).get("step_scale",1.0))

func pose(actor: Dictionary, job: Dictionary, actors: Dictionary, gesture: Dictionary = {}) -> Dictionary:
	var state: Dictionary = states.get(actor.id, {"phase": 0.0, "blink_until": 0.0, "step": 0.0})
	var facing: String = actor.get("facing", "down")
	var activity: String = actor.activity
	var movement:Dictionary=gesture.get("motion",{})
	var settled:bool=movement.is_empty() or (not movement.get("moving",false) and float(movement.get("still_seconds",1))>=.3)
	if working(actor,job):
		play_poses.erase(actor.id);play_phases.erase(actor.id)
		if activity.begins_with("play_") or activity in ["local_sit","local_rest","local_rise","resting","seated","rope_turn"]:activity="idle"
	elif settled and play_poses.has(actor.id):activity=str(play_poses[actor.id])
	if not settled:facing=str(movement.get("facing",facing))
	if settled and activity in ["idle", "local_look"] and attention_until > time:
		var other: Dictionary = actors.get("human", {}) if actor.id!="human" else {}
		if not other.is_empty() and other.region_id == actor.region_id:
			var offset := Vector2(other.position[0] - actor.position[0], other.position[1] - actor.position[1])
			if offset.length() < 7 and offset.length() > .2: facing = direction(offset)
	var frame := "%s_0" % facing
	var bob := 0.0
	var stretch := Vector2.ONE
	var fallback := facing + "_0"
	var lean := 0.0
	if activity == "walking":
		frame = "%s_%s" % [facing, [0, 1, 0, 2][int(float(state.step) * 8) % 4]]
		bob = -absf(sin(float(state.step) * 8 * PI)) * 1.4
		if gesture.get("running", false): lean = .07 if facing == "right" else -.07 if facing == "left" else .025
	elif activity in ["idle", "local_look", "assembled"]:
		# Stretch around the feet, not translation of the whole resident.
		stretch.y = 1.0 + sin(time * 1.9 + float(state.phase)) * .007
		stretch.x = 1.0 - (stretch.y - 1.0) * .35
		if time < float(state.blink_until): frame = "blink_" + facing
		if activity != "assembled" and gesture.get("thinking_allowed",false) and float(state.get("activity_age",0)) >= 10.0:
			if time >= float(state.get("next_think", 0.0)):
				state["think_started"] = time;state["think_until"] = time + 4.5;state["next_think"] = time + 40.0
			if time < float(state.get("think_until", 0.0)):
				frame = "think_down_" + str(int((time-float(state.think_started))*2.0) % 3)
		else: state["think_until"] = 0.0
	if activity == "local_pick_flower":
		var progress: float = float(gesture.get("progress", 0))
		var bend := sin(clampf(progress * 1.2, 0, 1) * PI)
		frame = "flower_pick_" + facing
		fallback = "pickup_" + facing
		stretch = Vector2(1.0 + bend * .025, 1.0 - bend * .09)
		lean = bend * (.06 if facing == "right" else -.06 if facing == "left" else .0)
	elif activity == "local_offer_flower":
		frame = "flower_offer_" + facing
		var amount := sin(clampf(float(gesture.get("progress", 0)), 0, 1) * PI)
		stretch = Vector2(1.0, 1.0 + amount * .018)
		bob = -amount * 1.2
	elif activity == "local_stretch":
		# Small shoulder/body stretch from the resident's own idle artwork.
		var amount := sin(clampf(float(state.get("activity_age", 0)) / 2.8, 0, 1) * PI)
		stretch = Vector2(1.0 - amount * .025, 1.0 + amount * .045)
		frame = "blink_" + facing
	elif activity in ["local_sit", "local_rest", "local_rise"]:
		frame = "up_0" if actor.region_id.begins_with("room.") and facing == "up" else "rest_empty"
		stretch.y = 1.0 + sin(time * 1.8 + float(state.phase)) * .007
		if frame == "up_0": stretch.y *= .78
	elif activity == "chopping":
		var phase := fmod(float(job.get("time", 0)), .8)
		frame = "chop_%s_%s" % [facing, 0 if phase < .48 else 1 if phase < .62 else 2]
	elif activity in ["picking_up", "putting_down"]: frame = "pickup_" + facing
	elif activity == "sitting_down": frame = "sitting_down" if float(job.get("time", 0)) > .12 else "down_0"
	elif activity == "standing_up": frame = "standing_up" if float(job.get("time", 0)) < .36 else "down_0"
	elif activity == "dancing":
		frame="%s_%s"%[["down","left","down","right"][int(time*.6)%4],1+int(time*3)%2]
		bob=-absf(sin(time*5))*4
		stretch=Vector2(1.0+sin(time*5)*.025,1.0-sin(time*5)*.025)
	elif activity == "swinging":frame="rest_empty"
	elif activity in ["eating", "seated"]:
		var meal_time := float(job.get("time", 0))
		frame = "seated_bite" if activity == "eating" and fmod(meal_time, 2.6) > 1.6 else "seated_idle"
		if activity == "seated":frame="rest_empty"
		if activity == "eating" and fmod(time, 5.0) < 1.3:
			for other in actors.values():
				if other.id == actor.id or other.region_id != actor.region_id or other.activity not in ["eating", "seated"]: continue
				var offset := Vector2(other.position[0] - actor.position[0], other.position[1] - actor.position[1])
				if offset.length() < 7: frame = "seated_right" if offset.x > 0 else "seated_left"
		stretch.y = 1.0 + sin(time * 1.7 + float(state.phase)) * .006
	elif activity in ["lighting", "grilling"]: frame = "%s_%s" % [activity, int(time * 3 + float(state.phase)) % 2]
	elif activity in ["fire_sit","fire_squat","fire_eat"]:
		var action:String="eat" if activity=="fire_eat" else "squat" if activity=="fire_squat" else "sit"
		frame="fire_%s_%s_%s"%[action,facing,int(time*2)% (2 if action=="sit" else 3)]
		fallback="fire_%s_down_%s"%[action,int(time*2)% (2 if action=="sit" else 3)]
		stretch.y=1.0+sin(time*1.7+float(state.phase))*.006
	elif activity in ["fish_cast","fish_wait","fish_bite","fish_reel"]:
		frame=activity+"_"+facing
		fallback="pickup_"+facing if activity!="fish_wait" else facing+"_0"
	elif activity=="gesture_wave":
		var amount:float=sin(clampf(float(state.get("activity_age",0))/float(gestures.wave.duration),0,1)*PI)
		frame=facing+"_0";bob=-amount*float(gestures.wave.bounce_pixels);lean=amount*float(gestures.wave.lean)*( -1.0 if facing=="left" else 1.0)
	elif activity=="gesture_stretch":
		var amount:float=sin(clampf(float(state.get("activity_age",0))/float(gestures.stretch.duration),0,1)*PI)
		frame=facing+"_0";stretch=Vector2(lerpf(1.0,float(gestures.stretch.scale_x),amount),lerpf(1.0,float(gestures.stretch.scale_y),amount))
	elif activity == "watering": frame = "grilling_%s" % (int(time*3)%2)
	elif activity == "gathering":
		var reach:float=sin(PI*clampf(fposmod(float(job.get("time",0)),1.0),0.0,1.0))
		frame="pickup_"+facing
		fallback=facing+"_0"
		lean=(.13 if facing in ["left","down"] else -.13)*reach
		stretch.y=1.0-.18*reach
		bob=9*reach
	elif int(actor.carry.get("wood", 0)) > 0:
		frame = "carry_" + facing
		if activity == "walking": frame += "_%s" % (int(float(state.step) * 8) % 2)
	if settled and activity in ["play_lie","play_cute","play_jump","rope_turn","play_squat","play_kick"]:
		var phase:float=float(play_phases.get(actor.id,fposmod(time*.5,1)))
		frame=facing+"_0";fallback=frame;lean=0;bob=0;stretch=Vector2.ONE
		state["play_style"]=activity
		state["play_land"]=0.0
		if activity in ["play_lie","play_squat"]:
			frame="seated_idle" if facing=="down" else "up_0" if facing=="up" else "seated_"+facing
		elif activity in ["play_cute","play_jump","play_kick"]:
			if activity=="play_cute":phase=fposmod(phase*2,1)
			bob=-22*sin(clampf((phase-.25)/.5,0,1)*PI)
			state["play_land"]=maxf(0,1-absf(phase-.8)/.1)
			stretch=Vector2(1+.09*state.play_land,1-.10*state.play_land)
		elif activity=="rope_turn":lean=sin(phase*TAU)*.075
	else:state.erase("play_style")
	if job.get("intent")=="play_gomoku" and job.get("step")=="using":
		frame="rest_empty";stretch.y=.78
		fallback=facing+"_0";lean=sin(time*1.7+float(state.phase))*.018
	var result:Dictionary={"frame": frame, "fallback": fallback, "bob": bob, "scale": stretch, "lean": sin(time * 9) * .025 if activity == "building" else sin(time*5)*.04 if activity=="dancing" else lean,"facing":facing}
	if state.has("play_style"):
		result["play_style"]=state.play_style
		result["play_land"]=state.play_land
		result["play_lift"]=bob
	enforce_direction(result,actor,movement)
	apply_gait(result,actor,gesture,state,settled)
	return result

func walk_column(id:String)->int:
	return posmod(int(float(states.get(id,{}).get("step",0))*6.0+0.000001),6)

func authored_walk_pose(pose:Dictionary,id:String,contact:Dictionary,velocity:Vector2,gait:Dictionary)->void:
	if contact.is_empty():return
	# Three columns per stance. Pin the supporting foot against real displacement;
	# retain gait lean/stretch and hunger posture, but compensate their foot offset.
	var foot:=Vector2(float(contact.pixel[0])-48,float(contact.pixel[1])-120)
	var rate:float=float(gait.get("step_scale",1.0))
	var within:float=fposmod(float(states.get(id,{}).get("step",0))*6.0,3.0)
	var correction:Vector2=-(foot*pose.scale).rotated(float(pose.lean))-velocity.normalized()*within*(WALK_STRIDE_PIXELS/6.0)/rate
	pose.sway=correction.x;pose.bob=correction.y

func run_column(id:String,gait:Dictionary,rushing:bool=false)->int:
	return int(float(states.get(id,{}).get("run_pixels",0))*float(gait.get("run_frames_per_step",gait.get("step_scale",1.0)))*(1.2 if rushing else 1.0)/12.0)%6

func run_transition(id:String)->Dictionary:
	var state:Dictionary=states.get(id,{})
	return {"start":clampf(1.0-(time-float(state.get("run_started",-10)))/.16,0,1),"stop":clampf(1.0-(time-float(state.get("run_stopped",-10)))/.3,0,1)}

func apply_gait(result:Dictionary,actor:Dictionary,gesture:Dictionary,state:Dictionary,settled:bool)->void:
	result["sway"]=0.0;result["dust"]=0.0
	var gait:Dictionary=gesture.get("gait",{})
	if gait.is_empty():return
	var moving:bool=gesture.get("motion",{}).get("moving",actor.activity=="walking")
	if moving:
		var hunger:int=int(gesture.get("hunger",-1));var energy:float=float(gait.full_boost) if hunger==0 else float(gait.hungry_scale)*(0.75 if hunger>=3 else 1.0) if hunger>=2 else 1.0
		var phase:float=float(state.get("step",0))*8*PI;var landing:float=cos(phase*2)
		result.bob=-absf(sin(phase))*float(gait.bounce)*energy
		result.sway=sin(phase*.5)*float(gait.sway)*energy
		result.scale*=Vector2(1+float(gait.squash)*landing*.6*energy,1-float(gait.squash)*landing*energy)
		if hunger>=2:result.scale.y*=1-float(gait.head_drop)/128.0
		var side:float=-1.0 if result.facing=="left" else 1.0 if result.facing=="right" else .2
		result.lean=sin(phase*.5)*.018*energy+float(gait.lean)*side
		result.dust=float(gait.dust)*energy
		if gesture.get("running",false):
			var transition:Dictionary=run_transition(actor.id)
			var run_phase:float=float(state.get("run_pixels",0))*float(gait.get("run_frames_per_step",gait.step_scale))/12.0*PI/3.0
			var flight:float=pow(absf(sin(run_phase)),.65)
			var rush:float=1.3 if gesture.get("rushing",false) else 1.0
			result.bob=-1.5-flight*float(gait.get("run_bounce",gait.bounce))*energy+transition.start*3.0
			result.sway=float(gait.get("run_sway",0))*sin(run_phase)
			result.lean=side*(float(gait.get("run_lean",gait.lean))*rush+transition.start*.09)
			var widen:float=float(gait.get("run_stretch",gait.squash))*sin(run_phase*2)
			result.scale=Vector2(1+widen,1-widen*.5-transition.start*.05)
			result.dust=float(gait.get("run_dust",gait.dust))*rush
	elif run_transition(actor.id).stop>0:
		var brake:float=run_transition(actor.id).stop
		result.frame=result.facing+"_0"
		result.lean=(-1.0 if result.facing=="left" else 1.0)*float(gait.get("run_lean",gait.lean))*brake
		result["brake_dust"]=brake*float(gait.get("run_dust",gait.dust))
	elif settled and actor.activity in ["idle","local_look"] and actor.carry.is_empty() and attention_until<=time:
		# The body must already be stopped. These are existing directional frames,
		# not an extra movement, route, authored animation or personality decision.
		var spin_every:float=gait.spin_every;var look_every:float=gait.look_every if float(gait.look_every)>0 else 28.0/float(gait.step_scale)
		if spin_every>0:
			var phase:float=fposmod(time+float(state.phase),spin_every)
			if phase<float(gait.spin_seconds):result.frame=["down","left","up","right"][mini(3,int(phase/float(gait.spin_seconds)*4))]+"_0";result["idle_spin"]=true
		elif look_every>0:
			var phase:float=fposmod(time+float(state.phase),look_every)
			if phase<float(gait.look_seconds):result.frame=["left","right"][int(phase/float(gait.look_seconds)*2)%2]+"_0";result["idle_glance"]=true

func enforce_direction(result:Dictionary,actor:Dictionary,movement:Dictionary)->void:
	if movement.is_empty() or (not movement.get("moving",false) and float(movement.get("still_seconds",1))>=.3):return
	var facing:String=str(movement.get("facing",actor.get("facing","down")))
	var state:Dictionary=states.get(actor.id,{"step":0.0})
	result.facing=facing;result.fallback=facing+"_0"
	result.frame=facing+"_"+str([0,1,0,2][int(float(state.step)*8)%4]) if movement.get("moving",false) else facing+"_0"
	if int(actor.carry.get("wood",0))>0:result.frame="carry_"+facing+("_"+str(int(float(state.step)*8)%2) if movement.get("moving",false) else "")

static func direction(offset: Vector2) -> String:
	if absf(offset.x) > absf(offset.y): return "right" if offset.x > 0 else "left"
	return "down" if offset.y > 0 else "up"

func authored_run_pose(pose:Dictionary,id:String,gait:Dictionary,contact:Dictionary,velocity:Vector2,rushing:bool=false)->void:
	# Only independent imported art uses this branch. Fallback gait stays intact.
	var start:float=float(run_transition(id).start)
	pose.bob=start*3.0;pose.scale=Vector2(1,1-start*.05);pose.sway=0.0;pose.lean*=.22
	if contact.is_empty():return
	var foot:Vector2=Vector2(float(contact.pixel[0])-48,float(contact.pixel[1])-120)
	var rate:float=float(gait.get("run_frames_per_step",gait.get("step_scale",1.0)))*(1.2 if rushing else 1.0)
	var phase:float=fposmod(float(states.get(id,{}).get("run_pixels",0))*rate/12.0,3.0)
	var correction:Vector2=-(foot*pose.scale).rotated(pose.lean)
	if not contact.airborne:correction-=velocity.normalized()*phase*12.0/rate
	else:correction.y=-7.0
	pose.sway=correction.x;pose.bob=correction.y+start*3.0
