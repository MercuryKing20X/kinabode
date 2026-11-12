extends RefCounted
static func complete(id:String,item:Dictionary)->bool:
	var base:String=ProjectSettings.globalize_path("res://").path_join("../production/art/run-v1")
	# DIRECTION2026-11-11: new default Orange is an additional independent work.
	# Existing14 source/review paths and every original validation below are retained.
	if id=="orange-sunflower-girl":
		base=ProjectSettings.globalize_path("res://").path_join("../production/art/orange-cohesive-20261111")
		if item.get("status")!="independent" or item.get("source_file")!="run-source.png" or item.get("asset")!="orange-sunflower-girl.png":return false
		if FileAccess.get_sha256("res://content/run-animations/orange-sunflower-girl.png")!=item.get("atlas_sha256",""):return false
	var source:String=base.path_join(str(item.get("source_file","")))
	if str(item.get("source_file","")).is_empty() or not FileAccess.file_exists(source) or FileAccess.get_sha256(source)!=item.get("source_sha256",""):return false
	var work:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+id+".json"))
	if not work is Dictionary:return false
	var values:PackedStringArray=[]
	for v in work.frames.down_0[0].pixels:values.append(str(int(v)))
	if ",".join(values).sha256_text()!=item.get("base_frame_sha256","") or "|".join(PackedStringArray(work.palette)).sha256_text()!=item.get("base_palette_sha256",""):return false
	var reviews:Variant=JSON.parse_string(FileAccess.get_file_as_string(base.path_join("run-review.json")))
	if not reviews is Dictionary or not reviews.has(id):return false
	var rows:Variant=reviews[id].get("directions",[])
	if not rows is Array or rows.size()!=4:return false
	for row in range(4):
		if not rows[row] is Array or rows[row].size()!=6:return false
		for col in range(6):
			if rows[row][col]!=["down","left","right","up"][row]:return false
	return item.get("frames")==24 and item.get("review_file")=="run-review.json"
static func valid_manifest(works:Dictionary)->bool:
	for id in works:
		var item:Dictionary=works[id]
		if item.get("status")=="independent":
			if not complete(id,item):return false
		elif item.get("status")!="unavailable":return false
	return true
