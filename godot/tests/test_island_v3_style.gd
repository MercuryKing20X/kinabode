extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-style.json"))
	check(data.render_only and data.palette.size()==48,"48-color render-only grammar")
	var unique:Dictionary={}
	for entry in data.palette:unique[entry.hex]=true
	check(unique.size()==48 and data.palette.all(func(c):return Color.html_is_valid(c.hex)),"48 valid unique colors")
	check(data.tile_pixels==32 and data.half_level_pixels==16,"tile and half-height convention")
	check(data.integer_scales.all(func(n):return n>0 and n==floor(n)),"integer scales only")
	check(data.shadow.direction.size()==2 and data.shadow.direction[0]==3 and data.shadow.direction[1]==2 and data.shadow.opacity==.22 and data.shadow.contact_width==2,"shared shadow grammar")
	check(data.roads.main.width==2 and data.roads.secondary.width==1 and data.roads.trail.width==.6,"road hierarchy")
	check(data.density.focus==1 and data.density.small_props.size()==2 and data.density.small_props[0]==2 and data.density.small_props[1]==4,"clustered density")
	check(data.personalities.size()==4 and data.day_tints.size()==4,"personality yards and time palettes")
	var image:=Image.load_from_file(OS.get_environment("HABITAT_PALETTE_OUTPUT"))
	check(image.get_size()==Vector2i(560,424),"generated palette sheet exact dimensions")
	print("Island v3 style: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
