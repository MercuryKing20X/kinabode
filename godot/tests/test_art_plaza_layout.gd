extends SceneTree
const Layout=preload("res://scripts/art_study_layout.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/scenes.json")).A
	var well:=Layout.point(config,Layout.by_id(config,"well"));var fire:=Layout.point(config,Layout.by_id(config,"fire"));var stove:=Layout.point(config,Layout.by_id(config,"stove"))
	check(well.x<config.camera[0]-2,"well is left of plaza center")
	check(fire.distance_to(stove)<3,"fire and stove are adjacent")
	check(config.shortcut[0][0]==well.x and config.shortcut[-1][0]==fire.x and absf(fire.x-well.x)>5 and absf(fire.y-well.y)>1,"real visual diagonal between shared anchors")
	var gaps:Array=[well.distance_to(fire),fire.distance_to(stove),Layout.point(config,Layout.by_id(config,"crates")).distance_to(Layout.point(config,Layout.by_id(config,"logs")))]
	check(absf(gaps[0]-gaps[1])>.5 and absf(gaps[1]-gaps[2])>.5,"at least three different neighboring spacing values")
	var lamps:Array=config.props.filter(func(p):return p.kind=="lamp")
	check(lamps.size()>=3 and absf(lamps[0].position[1]-lamps[1].position[1])>3,"lamps are not a symmetric row")
	check(absf(Layout.point(config,Layout.by_id(config,"gazebo")).x-config.camera[0])>5 and absf(Layout.point(config,Layout.by_id(config,"notice")).y-config.camera[1])>2,"two independent asymmetries: pavilion and entry board")
	var sizes:Dictionary={}
	for prop in config.props:
		if prop.has("size_class"):sizes[prop.size_class]=true
	check(sizes.size()>=3,"three prop size classes")
	check(Layout.by_id(config,"well").nominal_pixels[0]>Layout.by_id(config,"notice").nominal_pixels[0] and Layout.by_id(config,"notice").nominal_pixels[0]>Layout.by_id(config,"bucket").nominal_pixels[0]*3,"well largest, board medium, bucket visibly small")
	var chess:=Layout.point(config,Layout.by_id(config,"chess"));var tree:Vector2=Layout.point(config,config.foliage[0])
	check(chess.distance_to(tree)<5,"chess corner next to canopy")
	var clear:bool=true;var center:=Vector2(config.notice_clearance.center[0],config.notice_clearance.center[1])
	for prop in config.props:
		if prop.id!="notice" and Layout.point(config,prop).distance_to(center)<config.notice_clearance.radius:clear=false
	check(clear,"entrance board has an empty standing patch")
	check(config.props.all(func(p):return not p.has("items") and not p.has("invested")),"visual objects contain no material grants or fake progress")
	print("Lived-in plaza layout: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
