extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Motion=preload("res://scripts/actor_motion.gd")
const Catalog=preload("res://scripts/workshop_catalog.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var world:=World.new();var library:=Library.new();library.configure(dir);world.library=library
	for id in ["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl","ai-gpt","ai-claude","ai-gemini","ai-grok","ai-deepseek","ai-glm","ai-qwen","ai-kimi"]:
		var art:Dictionary=library.artworks[id]
		check(library.valid(art),id+" valid")
		check(Catalog.frames(art,"生活","蹲下思考","down").size()==3,id+" navigable")
		if id.begins_with("ai-"):check(art.frame_status.frames.think_down_0=="placeholder",id+" placeholder")
	var actor:Dictionary=world.actors.codex;actor.activity="idle";var motion:=Motion.new();var saw:=false
	for i in range(600):
		world.advance(.1);motion.advance(.1,world.actors)
		var pose:Dictionary=motion.pose(actor,{},world.actors,{"thinking_allowed":true})
		if str(pose.frame).begins_with("think_"):saw=true
	check(saw,"idle motion can think")
	var timing:=Motion.new();var duration:=0.0
	for tick in range(220):
		world.advance(.1);timing.advance(.1,world.actors)
		if str(timing.pose(actor,{},world.actors,{"thinking_allowed":true}).frame).begins_with("think_"):duration+=.1
	check(duration>=3.0 and duration<=6.0,"one undisturbed idle thought lasts 3–6 seconds")
	actor.activity="chopping"
	check(not str(motion.pose(actor,{},world.actors,{"thinking_allowed":true}).frame).begins_with("think_"),"work always wins")
	actor.activity="idle"
	check(not str(motion.pose(actor,{},world.actors,{"thinking_allowed":false}).frame).begins_with("think_"),"blocked presentation stays silent")
	print("Think motion: ",checks," checks, failed=",failed);quit(1 if failed else 0)
