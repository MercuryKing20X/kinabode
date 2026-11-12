extends SceneTree
const Library=preload("res://scripts/character_library.gd")
const Blueprint=preload("res://scripts/blueprint_rules.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var library:=Library.new();library.configure(directory)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/house-source.json"))
	var roof_geometry:Dictionary={}
	for plan in source.profiles.values():roof_geometry[JSON.stringify(plan.roof_polygons)]=true
	check(roof_geometry.size()==5,"five different authored roof contours, not palette-only variants")
	check(not library.artworks.has("study-house-gentle"),"new study works do not enter live workshop/catalog automatically")
	var approved:Dictionary={};approved["#00000000"]=true
	for parent in source.parents:
		var master:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/works/"+parent+".json"))
		for color in master.palette:approved[str(color).to_lower()]=true
	var footprints:Dictionary={};var roofs:Dictionary={};var appearances:Dictionary={};var openings:Dictionary={};var yards:Dictionary={}
	for id in ["human","gentle","curious","lively","quiet"]:
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/houses/"+id+".json"))
		check(library.valid(art),"existing editable building contract "+id)
		check(art.structure.size()==4 and Blueprint.quote(art.structure).ok,"unchanged width/depth/floors/porch quote "+id)
		footprints[str(Blueprint.footprint(art.structure))]=true;roofs[art.roof_profile]=true
		openings[str(art.openings.doors.size())+":"+str(art.openings.windows.size())]=true;yards[JSON.stringify(art.yard)]=true
		var image:Image=library.render(art,"stage_4");appearances[image.get_data().hex_encode().sha256_text()]=true
		var original_colors:=true
		for color in art.palette:
			if Color(str(color)).a>0 and not approved.has(str(color).to_lower()):original_colors=false
		check(art.frames.size()==5 and original_colors,"five stage frames use only approved original cottage colors "+id)
		var distinct:Dictionary={}
		for stage in range(5):distinct[JSON.stringify(art.frames["stage_"+str(stage)])]=true
		check(distinct.size()==5,"foundation/frame/wall/roof/finish are distinct "+id)
		for box in art.openings.windows:
			check(image.get_pixel(int(box[0]+box[2]/2),int(box[1]+box[3]/2)).a>.9,"window really painted "+id)
	check(footprints.size()==5 and roofs.size()==5,"five different footprints and roof structures")
	check(openings.size()==5 and yards.size()==5,"different opening counts and yard plans")
	check(appearances.size()==5,"different final raster artwork, not reused original cottage")
	var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/works/cottage.json"));check(original.id=="cottage" and original.frames.has("stage_4"),"original template remains present")
	print("Authored house works: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
