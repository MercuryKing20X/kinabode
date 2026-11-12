extends SceneTree
const Motion=preload("res://scripts/actor_motion.gd")
func _initialize()->void:
	var m:=Motion.new()
	var actor:Dictionary={"id":"human","activity":"walking","facing":"left","carry":{},"appearance_id":"human-starter"}
	var actors:Dictionary={"human":actor}
	for col in 6:
		m.advance(.1,actors,{}, {"human":{"moving":true,"distance":.25}})
		assert(m.walk_column("human")==((col+1)%6))
	var before:int=m.walk_column("human")
	m.advance(10,actors,{}, {"human":{"moving":true,"distance":0.0}})
	assert(m.walk_column("human")==before,"no elapsed-time sliding")
	m.advance(.1,actors,{}, {"human":{"moving":false,"distance":0.0}})
	assert(m.walk_column("human")==0)
	var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var atlas:=preload("res://scripts/motion_atlas.gd").new()
	assert(atlas.manifests.walk.works.size()==13)
	for id in atlas.manifests.walk.works:
		actor["appearance_id"]=id;actor["appearance"]=id
		# Library's public appearance binding lives on actor.appearance_id.
		for facing in ["down","left","right","up"]:
			actor.facing=facing
			for col in 6:
				assert(atlas.texture("walk",lib,actor,col)!=null,"imported walk texture "+id)
				assert(not atlas.contact("walk",lib,actor,col).is_empty())
	var max_drift:=0.0
	for id in atlas.manifests.walk.works:
		actor.appearance_id=id
		for facing in ["left","right","up","down"]:
			actor.facing=facing
			var velocity:Vector2={"left":Vector2.LEFT,"right":Vector2.RIGHT,"up":Vector2.UP,"down":Vector2.DOWN}[facing]
			for i in range(1,240):
				var pixels:float=float(i)*.1
				m.states.human.step=pixels/48.0
				var contact:Dictionary=atlas.contact("walk",lib,actor,m.walk_column("human"))
				var pose:Dictionary={"scale":Vector2(1.01,.98),"lean":.02,"sway":0.0,"bob":0.0}
				m.authored_walk_pose(pose,"human",contact,velocity,{"step_scale":1.0})
				var foot:=Vector2(float(contact.pixel[0])-48,float(contact.pixel[1])-120)
				var at:Vector2=velocity*pixels+(foot*pose.scale).rotated(pose.lean)+Vector2(pose.sway,pose.bob)
				max_drift=maxf(max_drift,at.length())
	assert(max_drift<.001,"support foot stays planted under real displacement")
	FileAccess.open("/tmp/youqi-actions-review/foot-drift.json",FileAccess.WRITE).store_string(JSON.stringify({"appearances":13,"directions":4,"samples":12428,"max_pixels":max_drift,"limit":.001,"scope":"within one continuous stance, analytical draw transform; not measured visual silhouette"}))
	print("WALK_ATLAS PASS drift=",max_drift)
	quit()
