extends SceneTree
func _initialize()->void:
	var font:Font=load("res://assets/fonts/NotoSansSC.ttf");var folder:="res://content/intelligence/units/speech";var missing:Dictionary={};var unique:Dictionary={};var lines:=0
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".json"):continue
		var unit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file)))
		for line in unit.lines:
			lines+=1
			for index in range(line.length()):
				var code:int=line.unicode_at(index);unique[code]=true
				if code>32 and not font.has_char(code):missing[String.chr(code)]=file
	var output:=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if not output.is_empty():
		var f:=FileAccess.open(output.path_join("E-glyphs.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"font":"NotoSansSC.ttf","lines":lines,"unique_characters":unique.size(),"missing":missing},"  "));f.close()
	print("Speech glyph coverage: ",unique.size()," characters across ",lines," lines; missing=",missing)
	if not missing.is_empty():push_error("Authored dialogue contains unsupported font glyphs")
	quit(1 if not missing.is_empty() else 0)
