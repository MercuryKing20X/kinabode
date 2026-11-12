extends SceneTree
const Library=preload("res://scripts/character_library.gd")
var failed:=false
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failed=true;push_error(label)
func _initialize()->void:
	var data:String=OS.get_environment("HABITAT_DATA_DIR")
	assert(data.contains("youqi-test-"))
	var dir:String=data.path_join("characters");DirAccess.make_dir_recursive_absolute(dir)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/ai-glm.json"))
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/glm_legacy_direction_hashes.json"))
	var old:Dictionary=source.duplicate(true)
	for p in manifest.pairs:
		var value:Variant=old.frames[p.left];old.frames[p.left]=old.frames[p.right];old.frames[p.right]=value
	var path:String=dir.path_join("ai-glm.json")
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(old));f.close()
	var before:String=FileAccess.get_sha256(path)
	var lib:=Library.new();lib.configure(data)
	for p in manifest.pairs:
		check(lib.artworks["ai-glm"].frames[p.left]==source.frames[p.left] and lib.artworks["ai-glm"].frames[p.right]==source.frames[p.right],"untouched legacy pair corrected in memory")
	check(FileAccess.get_sha256(path)==before,"existing editable artwork file remains unchanged")
	old.frames[manifest.pairs[0].left][0].pixels[0]=1
	f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(old));f.close()
	before=FileAccess.get_sha256(path);lib=Library.new();lib.configure(data)
	check(PackedByteArray(lib.artworks["ai-glm"].frames[manifest.pairs[0].left][0].pixels)==PackedByteArray(old.frames[manifest.pairs[0].left][0].pixels) and PackedByteArray(lib.artworks["ai-glm"].frames[manifest.pairs[0].right][0].pixels)==PackedByteArray(old.frames[manifest.pairs[0].right][0].pixels),"edited pair not rewritten")
	check(FileAccess.get_sha256(path)==before,"edited work remains byte-identical on disk")
	print("GLM legacy in-memory correction: ",checks," checks, failed=",failed)
	quit(1 if failed else 0)
