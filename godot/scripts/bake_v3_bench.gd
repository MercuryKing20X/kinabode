extends SceneTree
const LocalText=preload("res://scripts/localization.gd")
## Transcribe the already-authored bench prop into an existing Leisure sit template.
func _initialize()->void:
	var props:=preload("res://scripts/study_prop_atlas.gd").new()
	props.build(JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-style.json")))
	var image:Image=props.textures.bench.get_image();var palette:Array=["#00000000"];var pixels:Array=[];var lookup:Dictionary={"#00000000":0}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color:Color=image.get_pixel(x,y);var key:String="#"+color.to_html(true) if color.a>0 else "#00000000"
			if not lookup.has(key):lookup[key]=palette.size();palette.append(key)
			pixels.append(lookup[key])
	var layer:Dictionary={"id":"original-bench","name":LocalText.text("ui.bake_v3_bench.original_bench_pixels_reused"),"visible":true,"pixels":pixels}
	var art:Dictionary={"schema_version":1,"id":"play-bench","name":LocalText.text("ui.bake_v3_bench.island_wooden_bench"),"kind":"facility","facility_type":"recreation","revision":1,"width":image.get_width(),"height":image.get_height(),"anchor":[int(props.anchors.bench.x),int(props.anchors.bench.y)],"palette":palette,"frames":{"idle":[layer],"active":[layer.duplicate(true)]},"recreation":{"width":4,"depth":3,"entry":[0,1.5],"slots":[[-.8,0],[.8,0]],"obstacles":[[-2,-1,4,.3]],"behavior":"sit","seconds":30},"source":"Existing authored bench from island_sample_props/study_prop_atlas, no new shape or image-model calls"}
	assert(preload("res://scripts/character_library.gd").new().valid(art))
	var file:=FileAccess.open("res://content/home-v3/works/play-bench.json",FileAccess.WRITE);file.store_string(JSON.stringify(art));print("Existing bench transcribed to a real sit facility.");quit()
