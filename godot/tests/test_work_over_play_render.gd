extends SceneTree
const IDS=["human-starter","white-haired-girl","blue-haired-girl","orange-sunflower-girl","black-scarf-girl","ai-gpt","ai-claude","ai-gemini","ai-grok","ai-deepseek","ai-glm","ai-qwen","ai-kimi"]
class OfflineLink extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_message:Dictionary)->bool:return false
var failures:=0
var g:Node
var w:RefCounted
var out:=""
var results:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("WORK_FRAME ",ok," ",label)
	if not ok:failures+=1
func visual(id:String,save_name:String="")->Dictionary:
	g.view.center=w.point(w.actors[id]);g.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	if not save_name.is_empty() and not out.is_empty():
		var img:Image=root.get_texture().get_image()
		var p:Vector2=g.view.screen(w.point(w.actors[id]))
		img.get_region(Rect2i(Vector2i(p)-Vector2i(91,131),Vector2i(182,166))).save_png(out.path_join(save_name+".png"))
	return g.view.submitted_actor_frames.get(id,{}).duplicate(true)
func isolate(id:String)->void:
	w.work.stop(id,false);w._routes.erase(id);w.actors[id].activity="idle"
	for other in w.director.routines:w.director.routines[other].enabled=false
func start(id:String,action:String)->bool:
	var a:Dictionary=w.actors[id]
	if action=="fish":
		var shore:Array=w.fishing.nearby_shores(id,1)
		if shore.is_empty():return false
		a.position=shore[0].position.duplicate()
		return w.fishing.start(id).ok
	var targets:Array=w.objects.values().filter(func(row):return row.kind=="tree" and row.region_id=="home" and row.status=="mature") if action=="chop" else w.all_mushrooms().values().filter(func(row):return row.region_id=="home" and int(row.amount)>0)
	targets.sort_custom(func(a,b):return w.point(a).distance_squared_to(w.point(w.actors[id]))<w.point(b).distance_squared_to(w.point(w.actors[id])))
	for target in targets.slice(0,18):
		var args:Dictionary={"intent":"chop" if action=="chop" else "forage","target_id":target.id}
		w.host_issuing[id]=true
		var result:Dictionary=w.command(id,args)
		w.host_issuing.erase(id)
		if result.ok:return true
	return false
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-") or DisplayServer.get_name()=="headless":quit(2);return
	OS.set_environment("HABITAT_OPENING","standard")
	out=OS.get_environment("HABITAT_WELCOME_MEDIA")
	root.size=Vector2i(960,640)
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,directory)
	pool.factory=func(_id):return OfflineLink.new()
	g=load("res://scenes/main_v3.tscn").instantiate()
	g.dialogue_adapter_factory=func(_id,_scope):return OfflineLink.new()
	root.add_child(g);g.save_enabled=false;g.set_process(false);g.memory_life.set_process(false);g.island_hud.hide()
	w=g.world
	g.view.set_process(false);g.view.follow_player=false;g.view.inspect_actor_frames=true;g.view.zoom=1.05
	var id:="codex"
	var origin:Array=w.actors[id].position.duplicate()
	await process_frame
	for appearance in IDS:
		for action in ["chop","gather","fish"]:
			isolate(id)
			w.actors[id].position=origin.duplicate();w.actors[id].appearance_id=appearance
			w.advance(.35)
			g.view.motion.play_poses[id]="play_squat";g.view.motion.play_phases[id]=.4
			var before:Dictionary=await visual(id)
			check(before.get("play",false),appearance+" "+action+" starts in displayed play pose")
			check(start(id,action),appearance+" real command accepted "+action)
			var proper:Array=["fish_cast","fish_wait","fish_bite","fish_reel"] if action=="fish" else ["chopping"] if action=="chop" else ["gathering"]
			for i in 200:
				w.advance(.1)
				if w.actors[id].activity in proper and not w._routes.has(id) and w.motion_state(id).get("still_seconds",0)>=.3:break
			var row:Dictionary=await visual(id,appearance+"-"+action)
			var expected:String={"chop":"chop-animations","gather":"gather-animations","fish":"fishing-animations"}[action]
			var native_fallback:bool=action=="chop" and str(row.get("frame","")).begins_with("chop_")
			if action=="gather" and row.get("sheet","").is_empty():native_fallback=absf(float(row.get("tilt",0)))>.04 and float(row.get("height_scale",1))<.94
			check(not row.get("play",true) and not g.view.motion.play_poses.has(id) and (row.get("sheet")==expected or native_fallback),appearance+" final submitted "+action+" "+str(row))
			results.append({"appearance":appearance,"action":action,"rendered":row,"previous":before})
	isolate(id)
	if not out.is_empty():
		var file:=FileAccess.open(out.path_join("work-frames.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "))
	print("WORK_FAILURES ",failures);g.queue_free();await process_frame;quit(1 if failures else 0)
