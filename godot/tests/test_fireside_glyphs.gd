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
	# All new bilingual lifecycle scenes use the exact font installed in the game,
	# including every character in their ASCII kaomoji (no system fallback).
	var scenes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/barbecue-scenes.json")).scenes
	var count:=0;var faces:=0;var invalid:=false
	if scenes.keys().size()!=4:invalid=true
	for tag in scenes:
		if scenes[tag].keys().size()!=8:invalid=true
		for scene in scenes[tag]:
			var rows:Array=scenes[tag][scene];var seen_zh:Dictionary={};var seen_en:Dictionary={}
			if rows.size()<8:invalid=true
			for row in rows:
				count+=1
				if "(" in row.zh or ":-)" in row.zh:faces+=1
				if seen_zh.has(row.zh) or seen_en.has(row.en) or row.en==row.zh:invalid=true
				seen_zh[row.zh]=true;seen_en[row.en]=true
				for locale in ["zh","en"]:
					lines+=1
					for index in range(row[locale].length()):
						var code:int=row[locale].unicode_at(index);unique[code]=true
						if code>32 and not font.has_char(code):missing[String.chr(code)]=tag+":"+scene+":"+locale
	if count<256 or float(faces)/maxi(1,count)<.3 or float(faces)/maxi(1,count)>.38:invalid=true
	if invalid:push_error("Barbecue scenes require eight distinct bilingual lines per trait/scene and approximately one third kaomoji")
	var output:=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if not output.is_empty():
		var f:=FileAccess.open(output.path_join("E-glyphs.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"font":"NotoSansSC.ttf","lines":lines,"unique_characters":unique.size(),"missing":missing,"barbecue_scene_pairs":count,"kaomoji_pairs":faces},"  "));f.close()
	print("Speech glyph coverage: ",unique.size()," characters across ",lines," lines; missing=",missing)
	if not missing.is_empty():push_error("Authored dialogue contains unsupported font glyphs")
	quit(1 if invalid or not missing.is_empty() else 0)
