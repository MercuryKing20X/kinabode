extends SceneTree
const Eyes=preload("res://scripts/hungry_onlooker.gd")
var checks:=0
var failed:=false
class Hunger extends RefCounted:
	var index:=2
	var allowed:=true
	func rank(_id:String)->int:return index
	func can_follow(_id:String)->bool:return allowed
class Routine extends RefCounted:
	var chatter:=true
	var time:=20.0
	var visual_quiet_until:=0.0
	var busy:=false
	func blocked()->bool:return busy
class Fire extends RefCounted:
	var lit:=true
	var state:Dictionary={"invited":["eater"]}
	var jobs:Dictionary={"eater":"actual-job"}
	var config:Dictionary={"seat_offsets":[[0,-3],[3,0],[0,3],[-3,0]]}
	func burning()->bool:return lit
class Life extends RefCounted:
	var station:Dictionary={"id":"home.barbecue","region_id":"home","position":[0,0]}
	var fireside:=Fire.new()
	func seats()->Array:return [{"position":[3,0]}]
class World extends RefCounted:
	var actors:Dictionary={"watcher":{"id":"watcher","region_id":"home","position":[5,0],"activity":"idle"},"human":{"id":"human","region_id":"home","position":[0,3],"activity":"fire_eat"}}
	var hunger:=Hunger.new()
	var _routes:Dictionary={}
	var movement:Dictionary={"moving":false,"still_seconds":1.0,"facing":"down"}
	var work:Dictionary={"jobs":{"eater":{"id":"actual-job","target_id":"home.barbecue","phase":"fire_eat"}}}
	var director:Dictionary={"routines":{"watcher":Routine.new()}}
	var fishing:Dictionary={"life":{"time":20.0,"quiet_until":{}}}
	var barbecues:Dictionary={"home.barbecue":Life.new()}
	func motion_state(_id:String)->Dictionary:return movement
	func point(what:Dictionary)->Vector2:return Vector2(what.position[0],what.position[1])
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var eyes:=Eyes.new();var w:=World.new();var life:RefCounted=w.barbecues["home.barbecue"]
	var original:Dictionary={"actors":w.actors.duplicate(true),"jobs":w.work.jobs.duplicate(true),"routes":w._routes.duplicate(true),"state":life.fireside.state.duplicate(true)}
	var cue:Dictionary=eyes.presentation(w,"watcher",0)
	check(not cue.is_empty() and cue.station_id=="home.barbecue" and cue.facing=="left","uninvited hungry settled observer outside actual seat circle watches active diner")
	check(eyes.presentation(w,"human",0).is_empty(),"human never gets an autonomous hunger cue")
	var nod:=false;var drool:=false
	for frame in range(240):
		cue=eyes.presentation(w,"watcher",frame*.05)
		nod=nod or cue.nod>0;drool=drool or cue.drool
	check(nod and drool,"existing frames gain a bounded swallow and occasional drool phase")
	check(w.actors==original.actors and w.work.jobs==original.jobs and w._routes==original.routes and life.fireside.state==original.state,"presentation changes no actor inventory route job invitation or fire state")
	w.hunger.index=1;check(eyes.presentation(w,"watcher",0).is_empty(),"slightly hungry outside scope");w.hunger.index=3
	check(not eyes.presentation(w,"watcher",0).is_empty(),"very hungry uses same visual rule")
	w.movement.moving=true;check(eyes.presentation(w,"watcher",0).is_empty(),"real movement direction always wins");w.movement.moving=false
	w.movement.still_seconds=.29;check(eyes.presentation(w,"watcher",0).is_empty(),"original 0.3-second settle rule retained");w.movement.still_seconds=.3
	w._routes.watcher=[Vector2.ZERO];check(eyes.presentation(w,"watcher",0).is_empty(),"never replaces an existing follow route");w._routes.clear()
	w.work.jobs.watcher={"id":"unrelated"};check(eyes.presentation(w,"watcher",0).is_empty(),"never interrupts real work");w.work.jobs.erase("watcher")
	w.actors.watcher.position=[2,0];check(eyes.presentation(w,"watcher",0).is_empty(),"inside-seat-ring positions are not silently relocated");w.actors.watcher.position=[5,0]
	life.fireside.state.invited.append("watcher");check(eyes.presentation(w,"watcher",0).is_empty(),"invitation immediately removes watcher cue");life.fireside.state.invited.erase("watcher")
	w.hunger.allowed=false;check(eyes.presentation(w,"watcher",0).is_empty(),"original held question assembly stop gates retained");w.hunger.allowed=true
	var routine:RefCounted=w.director.routines.watcher
	routine.chatter=false;check(eyes.presentation(w,"watcher",0).is_empty(),"muted chatter remains quiet");routine.chatter=true
	routine.visual_quiet_until=21;check(eyes.presentation(w,"watcher",0).is_empty(),"stop visual quiet period retained");routine.visual_quiet_until=0
	routine.busy=true;check(eyes.presentation(w,"watcher",0).is_empty(),"occupied local behavior not overridden");routine.busy=false
	w.fishing.life.quiet_until.watcher=21;check(eyes.presentation(w,"watcher",0).is_empty(),"fishing stop quiet retained");w.fishing.life.quiet_until.clear()
	life.fireside.lit=false;check(eyes.presentation(w,"watcher",0).is_empty(),"cold fire never fabricates eating cue");life.fireside.lit=true
	w.work.jobs.eater.phase="fire_sit";check(eyes.presentation(w,"watcher",0).is_empty(),"warm gathering alone is not actual eating");w.work.jobs.eater.phase="fire_eat"
	w.work.jobs.eater.id="replacement-job";check(eyes.presentation(w,"watcher",0).is_empty(),"unowned replacement job is not eating proof");w.work.jobs.eater.id="actual-job"
	life.station.id="moon.barbecue";check(eyes.presentation(w,"watcher",0).is_empty(),"cannot borrow main fire eating proof for moon fire")
	w.work.jobs.eater.target_id="moon.barbecue";check(eyes.presentation(w,"watcher",0).station_id=="moon.barbecue","same presentation works at actual moon camp")
	w.actors.watcher.region_id="room.house";check(eyes.presentation(w,"watcher",0).is_empty(),"different physical region excluded");w.actors.watcher.region_id="home"
	var pose:Dictionary={"facing":"down","frame":"down_0","fallback":"down_0","bob":0.0,"scale":Vector2.ONE}
	eyes.apply(pose,eyes.presentation(w,"watcher",0));check(pose.facing=="left" and pose.frame=="left_0","existing directional frame faces actual food with no artwork edits")
	var bad:Dictionary=Eyes.DEFAULTS.duplicate(true);bad.speed=150;check(not Eyes.valid_config(bad),"unknown gameplay field rejected")
	bad=Eyes.DEFAULTS.duplicate(true);bad.radius=NAN;check(not Eyes.valid_config(bad),"nonfinite radius rejected")
	bad=Eyes.DEFAULTS.duplicate(true);bad.swallow_every=0;check(not Eyes.valid_config(bad),"invalid cadence rejected")
	for appearance in ["white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl","ai-gpt","ai-deepseek","ai-claude","ai-glm"]:
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+appearance+".json"))
		for facing in ["down","left","right"]:
			var mouth:Vector2=eyes.mouth_point(art,facing)
			check(mouth.is_finite() and mouth.x>=-art.anchor[0] and mouth.x<=art.width-art.anchor[0] and mouth.y>=-art.anchor[1] and mouth.y<0,"face anchor follows current "+appearance+" "+facing)
	print("Hungry onlooker: ",checks," checks; failed=",failed,"; isolated presentation fixture, not player-input evidence");quit(1 if failed else 0)
