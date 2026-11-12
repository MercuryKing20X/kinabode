extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var ids:Array=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl","ai-gpt","ai-claude","ai-deepseek","ai-gemini","ai-grok","ai-glm","ai-qwen","ai-kimi"]
	for id in ids:
		var art:Dictionary=lib.artworks[id]
		var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../production/art/barbecue-v2/"+id+".json.original"))
		check(lib.valid(art) and art.palette==original.palette,"new optional art validates without palette change "+id)
		for key in original.frames:
			# The user explicitly corrected GLM by swapping every existing side
			# pair. Compare each full layer and all pixels to its original partner;
			# every other frame and character still compares to its original key.
			var source_key:String=key
			if id=="ai-glm":
				var other:String=key.replace("left","right") if key.contains("left") else key.replace("right","left")
				if other!=key and original.frames.has(other):source_key=other
			check(art.frames[key]==original.frames[source_key],"all original frame layers and pixels unchanged "+id+":"+key)
		for action in ["squat","sit","eat"]:
			var key:String="fire_"+action+"_down_0"
			check(art.frames.has(key) and preload("res://scripts/workshop_catalog.gd").describe(key).group=="生活","new action reachable in original workshop navigation "+id)
			check(preload("res://scripts/workshop_catalog.gd").preview_frames(art,key).size()==(2 if action=="sit" else 3),"exact new preview sequence")
			check(art.frame_status.frames[key]==("placeholder" if id.begins_with("ai-") else "independent"),"honest original/placeholder marking")
	var motion:=preload("res://scripts/actor_motion.gd").new()
	var a:Dictionary={"id":"codex","region_id":"home","position":[0,0],"activity":"fire_eat","facing":"up","carry":{}}
	motion.advance(.2,{"codex":a})
	check(motion.pose(a,{},{}).frame.begins_with("fire_eat_up_") and motion.pose(a,{},{}).fallback.begins_with("fire_eat_down_"),"missing directional expression safely falls back to added front frames")
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=lib;assert(preload("res://scripts/world_opening.gd").apply(w,lib).ok)
	for life in w.barbecues.values():
		# An explicit host invitation instantiates the new seat configuration without fuel or food.
		check(life.fireside.invite([]).ok and life.seats().size()==(5 if life.station.id=="homelands.barbecue" else 8),"exact configured circular seats or five-person vacation table")
		for seat in life.seats():check(w.walkable(seat.region_id,w.point(seat)),"World can walk to every new circular seat "+seat.id)
	print("Fireside motion: ",checks," checks, failed=",failed);quit(1 if failed else 0)
