extends SceneTree
const Motion=preload("res://scripts/actor_motion.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var helper:=Helper.new();var world:RefCounted=helper.fresh(temp);var motion:=Motion.new()
	assert(Motion.valid_gestures(motion.gestures));assert(Motion.valid_gestures(Motion.GESTURE_DEFAULT))
	var invalid:Dictionary=motion.gestures.duplicate(true);invalid.wave.duration=0;assert(not Motion.valid_gestures(invalid))
	invalid=motion.gestures.duplicate(true);invalid.stretch.extra=1;assert(not Motion.valid_gestures(invalid))
	var ids=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl","ai-gpt","ai-deepseek","ai-claude","ai-glm","ai-gemini","ai-grok","ai-qwen","ai-kimi"]
	var checked:=0
	for id in ids:
		assert(world.library.artworks.has(id));var art:Dictionary=world.library.artworks[id]
		for facing in ["down","left","right","up"]:
			assert(art.frames.has(facing+"_0"))
			for activity in ["gesture_wave","gesture_stretch"]:
				var actor:Dictionary={"id":"test","activity":activity,"facing":facing,"region_id":"home","position":[0,0],"carry":{},"appearance_id":id}
				var duration:float=float(motion.gestures.wave.duration if activity=="gesture_wave" else motion.gestures.stretch.duration)
				for age in [0.0,duration*.5,duration,duration*2]:
					motion.states.test={"phase":0.0,"step":0.0,"blink_until":0.0,"activity_age":age}
					var pose:Dictionary=motion.pose(actor,{}, {}, {})
					assert(pose.frame==facing+"_0" and not str(pose.frame).begins_with("pickup_"))
					if activity=="gesture_wave" and is_equal_approx(age,duration*.5):assert(pose.bob<0 and absf(pose.lean)>0)
					if activity=="gesture_stretch" and is_equal_approx(age,duration*.5):assert(pose.scale.x<1 and pose.scale.y>1)
					checked+=1
	assert(checked==416);helper.free()
	print("Gesture v2: ",checked," standing-frame poses across 13 appearances and four directions")
	quit()
