extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/scenes.json"))
	var ground:RefCounted=load("res://scripts/polygon_study_ground.gd").new();ground.prepare(source.A)
	check(source.snapshot_only and ground.cache_builds==1,"snapshot-only continuous polygon ground prepared")
	for material in ["grass","sand","soil"]:
		var hashes:Dictionary={}
		for i in range(3):
			var image:Image=ground.textures[material+str(i)].get_image();hashes[image.get_data().hex_encode().sha256_text()]=true
		check(hashes.size()==3,"three authored material variants "+material)
	check(ground.commands[0].material=="water" and ground.commands[1].material=="sand0" and ground.commands[2].material=="grass0","original water-sand-grass polygon order")
	check(ground.commands.any(func(c):return c.kind=="brush"),"authored mottled edge overlay")
	check(ground.commands.any(func(c):return c.material=="soil2"),"visual wear and diagonal shortcut layer")
	var before: String=JSON.stringify(ground.commands)
	for frame in range(600):ground.prepare(source.A)
	check(ground.cache_builds==1 and JSON.stringify(ground.commands)==before,"600 reads reuse cached geometry and UV")
	ground.prepare(source.B);check(ground.cache_builds==2,"new study geometry invalidates only drawing cache")
	var world:RefCounted=load("res://scripts/world_state.gd").new()
	check(world.catalog.regions.home.size[0]==160 and not world.catalog.regions.has("art-studies"),"active island not replaced")
	check(not ground.has_method("walkable") and not ground.has_method("can_step"),"drawing has no collision or movement authority")
	print("Polygon ground study: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
