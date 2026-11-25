extends SceneTree

func _initialize()->void:
	var content:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/play-animations/manifest.json"))
	var motion:=ActorMotion.new()
	var failures:int=0
	var checks:int=0
	for id in content.works:
		var work:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+id+".json"))
		for facing in ["down","left","up","right"]:
			var motion_state:Dictionary={"motion":{"moving":false,"still_seconds":1.0}}
			for activity in ["play_jump","play_cute","play_lie","play_squat","rope_turn","play_kick","play_roll"]:
				var actor:Dictionary={"id":id,"facing":facing,"activity":activity,"carry":{}}
				motion.play_phases[id]=.49
				var pose:Dictionary=motion.pose(actor,{}, {},motion_state)
				var frame:String=pose.frame if work.frames.has(pose.frame) else pose.fallback
				var stance:String=facing+"_0"
				var seat:String="seated_idle" if facing=="down" else "seated_"+facing
				var good:bool=work.frames.has(frame) and frame in [stance,seat] and not pose.has("play_column")
				if activity=="play_roll":good=good and not pose.has("play_style")
				if activity=="play_jump":good=good and float(pose.bob)<-19
				if not good:
					failures+=1
					push_error("%s %s %s drew %s"%[id,facing,activity,frame])
				checks+=1
	print("Play source integrity: ",checks," cases, ",failures," failed")
	quit(1 if failures else 0)
