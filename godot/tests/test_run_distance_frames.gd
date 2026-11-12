extends SceneTree
const Motion=preload("res://scripts/actor_motion.gd")
func _initialize()->void:
	var motion:=Motion.new()
	var actor:Dictionary={"id":"fixture","activity":"walking"}
	var actors:Dictionary={"fixture":actor};var running:Dictionary={"fixture":true}
	var movement:Dictionary={"fixture":{"moving":true,"distance":.375}}
	motion.advance(.1,actors,running,movement)
	assert(motion.run_column("fixture",{})==1,"twelve physical pixels advance exactly one frame")
	motion.advance(5,actors,running,{"fixture":{"moving":true,"distance":0.0}})
	assert(motion.run_column("fixture",{})==1,"elapsed time without displacement never advances run frame")
	assert(motion.run_column("fixture",{"step_scale":2.0})==2,"gait changes visual stride, never World speed")
	motion.advance(.1,actors,{}, {"fixture":{"moving":false,"distance":0.0}})
	assert(motion.run_transition("fixture").stop>0,"stop produces short presentation-only dust")
	var atlases:=preload("res://scripts/motion_atlas.gd").new()
	assert(atlases.manifests.run.works.size()==15 and atlases.manifests.run.works.has("orange-sunflower-girl"),"all14 retained appearances plus the newly authorized Orange have explicit provenance")
	assert(preload("res://tests/run_art_provenance.gd").valid_manifest(atlases.manifests.run.works),"no fake generated art: independent requires source/hash and every reviewed direction; otherwise unavailable")
	print("Run distance frames: retained source/review contracts and newly authorized Orange passed")
	quit()
