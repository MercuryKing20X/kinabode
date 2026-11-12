extends SceneTree
const Provenance=preload("res://tests/run_art_provenance.gd")
const Atlas=preload("res://scripts/motion_atlas.gd")
const Library=preload("res://scripts/character_library.gd")
func _initialize()->void:
	var library:=Library.new();library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var atlas:=Atlas.new();var count:=0;var support_samples:=0;var maximum_error:=0.0
	for id in atlas.manifests.run.works:
		var spec:Dictionary=atlas.manifests.run.works[id]
		if spec.status!="independent":continue
		count+=1;assert(Provenance.complete(id,spec))
		for key in ["source_sha256","source_file","base_frame_sha256","base_palette_sha256","review_file"]:
			var invalid:Dictionary=spec.duplicate(true);invalid.erase(key);assert(not Provenance.complete(id,invalid),"missing evidence must reject independent")
		if id=="orange-sunflower-girl":
			var invalid_atlas:Dictionary=spec.duplicate(true);invalid_atlas.erase("atlas_sha256")
			assert(not Provenance.complete(id,invalid_atlas),"new authorized Orange also rejects missing actual atlas hash")
		var actor:Dictionary={"id":"fixture","appearance_id":id,"facing":"left"}
		assert(not atlas.spec("run",library,actor).is_empty(),"content-equivalent local copy matches")
		for col in range(6):
			assert(atlas.texture("run",library,actor,col)!=null,"formally imported texture")
			assert(not atlas.run_contact(library,actor,col).is_empty(),"every column has feet")
		var motion:=preload("res://scripts/actor_motion.gd").new()
		var gait:Dictionary={"step_scale":1.0,"run_frames_per_step":1.15}
		for facing in ["left","right","up","down"]:
			actor.facing=facing
			var direction:Vector2={"left":Vector2.LEFT,"right":Vector2.RIGHT,"up":Vector2.UP,"down":Vector2.DOWN}[facing]
			var columns:Dictionary={}
			var previous:=Vector2.ZERO;var previous_column:=-1;var previous_airborne:=true
			for tick in range(600):
				var distance:float=100+tick*260.0/240.0
				motion.states.fixture={"run_pixels":distance,"run_started":-10.0}
				var col:int=motion.run_column("fixture",gait);columns[col]=true
				var foot:Dictionary=atlas.run_contact(library,actor,col)
				var pose:Dictionary={"bob":-10.0,"sway":0.0,"scale":Vector2(1.04,.98),"lean":.2}
				motion.authored_run_pose(pose,"fixture",gait,foot,direction*260)
				var local:Vector2=Vector2(foot.pixel[0]-48,foot.pixel[1]-120)
				var rendered:Vector2=direction*distance+Vector2(pose.sway,pose.bob)+(local*pose.scale).rotated(pose.lean)
				if not foot.airborne and not previous_airborne and int(col/3)==int(previous_column/3):
					var error:float=rendered.distance_to(previous);support_samples+=1;maximum_error=maxf(maximum_error,error)
					assert(error<2.0,"rendered supporting foot remains planted under real displacement")
				previous=rendered;previous_column=col;previous_airborne=foot.airborne
			assert(columns.size()==6,"running displacement cycles all six columns")
		var copy:Dictionary=library.artworks[id].duplicate(true)
		library.artworks[id].frames.down_0[0].pixels[0]=1
		library.artworks[id].revision+=1
		assert(atlas.spec("run",library,actor).is_empty(),"edited pixel preserves fallback")
		library.artworks[id]=copy
	assert(count>=3,"first three must have real reviewed running art")
	assert(count==15 and atlas.manifests.run.works.has("orange-sunflower-girl"),"retained14 and new independent Orange all pass the full original run contract")
	print("Run atlas v4: ",count," independent sources, missing-proof rejection, exact-content copy matching, edited fallback, imported frames and feet passed")
	print("Supporting-foot transform samples=",support_samples," maximum drift pixels=",maximum_error)
	quit()
