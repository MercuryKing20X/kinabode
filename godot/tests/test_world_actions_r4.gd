extends SceneTree

const Pool=preload("res://scripts/connection_session_pool.gd")
class Stub extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_args:Dictionary)->bool:return false

var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func run()->void:
	var path:=OS.get_environment("HABITAT_DATA_DIR")
	if not path.begins_with("/tmp/") and not path.begins_with("/var/folders/"):quit(2);return
	set_meta("title_opening","showcase")
	Pool.obtain(self,path).factory=func(_id):return Stub.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game)
	game.set_process(false)
	game.save_enabled=false
	var w:RefCounted=game.world
	var door:Node=game.world_door
	var now:=Time.get_ticks_msec()
	var lease:Dictionary=door.command("claim",{"resident":"codex","client":"Offline action fixture"},now)
	check(lease.get("ok",false),"claim white")
	if not lease.get("ok",false):quit(1);return
	var followers:Array=w.activities.following.keys();followers.erase("npc.nora")
	check(w.activities.set_followers(followers,["npc.nora"]).ok,"player leaves the intended helper free from the showcase follow group")
	var args:Dictionary={"lease":lease.lease,"resident":"npc.nora","steps":[{"action":"wait","seconds":1}]}
	var accepted:Dictionary=door.command("ask_help",args,now+1)
	check(accepted.get("ok",false),"local resident accepts a bounded plan: "+str(accepted.get("error","")))
	if accepted.get("ok",false):
		for _i in 25:w.advance(.1)
		door._process(0)
		var events:Dictionary=door.event_result(lease.lease,0)
		check(events.events.any(func(e):return e.type=="help_finished" and e.data.result.get("status")=="completed"),"requester gets actual helper completion: "+str(w.director.brains["npc.nora"].intention.basic.result))
	var second:Dictionary=door.command("claim",{"resident":"npc.mira","client":"Second fixture"},now+2)
	check(second.get("ok",false),"claim second resident")
	args.resident="npc.mira"
	check(door.command("ask_help",args,now+3).get("error")=="resident_unavailable","claimed resident cannot be enlisted")
	w.director.brains["companion-2"].finish("interrupted","fixture_owner_switch")
	w.director.routines["companion-2"].interrupt(0)
	w.director.set_controller("companion-2","model")
	var native:Dictionary=door.act("companion-2",{"steps":[{"action":"wait","seconds":1}]},"native_world")
	check(native.get("ok",false),"native plan accepted by shared executor")
	if native.get("ok",false):
		for _i in 14:w.advance(.1)
		check(w.director.brains["companion-2"].intention.basic.result.get("id")==native.action_id,"native plan gets ordinary execution receipt")
	var layer:RefCounted=w.flower_creation.creations
	check(layer.structure_check("home.storage").get("error")=="protected_structure","warehouse stays protected")
	check(layer.structure_check("moon.bridge.east").get("error")=="protected_structure","bridge stays protected")
	check(layer.structure_check("home.house.01").get("error")=="protected_structure","house stays protected")
	var fire_id:="home.barbecue"
	var old_position:Vector2=w.point(w.barbecues[fire_id].station)
	var before:int=w.storage.count("wood")
	var demolition:Dictionary=door.command("act",{"lease":lease.lease,"steps":[{"action":"remove_structure","target":fire_id}]},now+4)
	check(demolition.get("ok",false),"camp demolition accepted")
	if demolition.get("ok",false):
		for _i in 700:
			w.advance(.1)
			if not w.standard.ready(fire_id):break
		check(not w.standard.ready(fire_id) and w.storage.count("wood")==before,"preset camp dismantled without invented refund")
		door._process(0)
		var at:=Vector2.INF
		for radius in range(2,14):
			for offset in [Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
				var point:Vector2=old_position.round()+offset
				if layer.relocate_camp("codex",fire_id,{"position":[point.x,point.y]})=="":at=point;break
			if at.is_finite():break
		check(at.is_finite(),"found different safe camp location")
		if at.is_finite():
			var rebuild:Dictionary=door.command("act",{"lease":lease.lease,"steps":[{"action":"rebuild_camp","target":fire_id,"position":[at.x,at.y]}]},now+1005)
			check(rebuild.get("ok",false),"camp rebuild accepted")
			for _i in 700:
				w.advance(.1)
				if w.standard.ready(fire_id):break
			check(w.standard.ready(fire_id) and w.point(w.barbecues[fire_id].station)==at and w.storage.count("wood")<before,"camp was physically rebuilt on its new site")
	print("WORLD_ACTIONS checks=",checks," failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
