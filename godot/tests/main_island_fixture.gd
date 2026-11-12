extends RefCounted
## The original main-island geometry/capacity regression fixture excludes optional expedition packs.
## Original assertions and all original stock/capacity/trees remain unchanged.
static func world()->RefCounted:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	assert(directory.contains("youqi-test-"))
	DirAccess.make_dir_recursive_absolute(directory)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/home-v3/world.json"))
	data.active_packs.erase("res://content/packs/dark.json")
	var path:String=directory.path_join("main-island-regression-manifest.json")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	return preload("res://scripts/world_state.gd").new(path)
