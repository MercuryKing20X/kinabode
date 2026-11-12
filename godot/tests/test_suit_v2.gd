extends SceneTree
func _initialize()->void:
	var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var a:Dictionary={"id":"human","role":"human","facing":"left","activity":"walking","carry":{},"appearance_id":"suit-hulk"}
	var atlas:=preload("res://scripts/motion_atlas.gd").new()
	for action in ["walk","run","chop","gather","eat","farm","gesture"]:
		for facing in ["down","left","right","up"]:
			a.facing=facing
			for col in int(atlas.manifests[action].columns):assert(atlas.texture(action,lib,a,col)!=null)
	var motion:=preload("res://scripts/actor_motion.gd").new()
	motion.advance(.1,{"human":a},{},{"human":{"moving":true,"distance":1.0}})
	var before:int=motion.walk_column("human")
	motion.advance(5,{"human":a},{},{"human":{"moving":true,"distance":0.0}})
	assert(motion.walk_column("human")==before)
	# Edited artwork opts out of every external atlas, including new farm and gestures.
	lib.artworks["suit-hulk"].frames.down_0[0].pixels[0]=1;lib.artworks["suit-hulk"].revision+=1
	for action in ["walk","run","farm","gesture"]:assert(atlas.texture(action,lib,a,0)==null)
	print("SUIT_V2 PASS imported actions, zero-distance freeze, edited artwork protection")
	quit()
