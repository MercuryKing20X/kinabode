extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
var failed:=false
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(temp)
	assert(Opening.apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.director.set_all_enabled(false)
	var center:Array=w.map_anchor("plaza.center");var start:=Vector2(center[0]-3,center[1]+10)
	var people:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
	for id in people:
		check(w.assign_appearance(id,people[id]),"host changes resident appearance "+id)
		var arrival:Dictionary=w.command(id,{"intent":"move","x":start.x,"y":start.y})
		check(arrival.ok,"normal World route to walking test "+id)
		for i in range(3000):
			w.advance(.05)
			if not w._routes.has(id):break
		for entry in [{"name":"left","v":Vector2.LEFT},{"name":"right","v":Vector2.RIGHT},{"name":"up","v":Vector2.UP},{"name":"down","v":Vector2.DOWN}]:
			var before:Vector2=w.point(w.actors[id]);var dest:Vector2=before+entry.v*1.2
			check(w.walkable("home",dest) and w.segment_clear("home",before,dest),"free movement path "+id+" "+entry.name)
			var result:Dictionary=w.command(id,{"intent":"move","x":dest.x,"y":dest.y});check(result.ok,"real movement "+id+" "+entry.name)
			w.advance(.05)
			var m:Dictionary=w.motion_state(id)
			check(m.moving and w.actors[id].facing==entry.name and m.facing==entry.name,"actual moving facing "+id+" "+entry.name)
			var motion:=preload("res://scripts/actor_motion.gd").new()
			var running:Dictionary={id:w.is_running(id)};var moves:Dictionary={id:m};var gaits:Dictionary={id:w.intelligence.gait(id)}
			motion.advance(.05,{id:w.actors[id]},running,moves,gaits)
			var pose:Dictionary=motion.pose(w.actors[id],{},w.actors)
			check(str(pose.frame).begins_with(entry.name+"_") and w.library.artworks[people[id]].frames.has(pose.frame),"worn art resolves correct direction "+id+" "+entry.name)
			for i in range(200):
				w.advance(.05)
				if not w._routes.has(id):break
	print("Nondefault appearance movement: ",checks," checks, failed=",failed)
	quit(1 if failed else 0)
