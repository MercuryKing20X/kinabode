extends SceneTree
const Comparison=preload("res://scripts/art_comparison.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var a:=Image.create(2,2,false,Image.FORMAT_RGB8);a.fill(Color.RED);var b:=Image.create(2,2,false,Image.FORMAT_RGBA8);b.fill(Color.BLUE)
	var joined:Image=Comparison.join(a,b)
	check(joined.get_size()==Vector2i(4,2),"join preserves source dimensions, no resizing")
	check(joined.get_pixel(0,0)==Color.RED and joined.get_pixel(3,1)==Color.BLUE,"left and right pixels copied exactly")
	check(a.get_format()==Image.FORMAT_RGB8,"source image never modified")
	check(Comparison.join(a,Image.create(3,2,false,Image.FORMAT_RGBA8))==null,"different sizes rejected instead of rescaled")
	var left:Dictionary={"camera_tile":[26,47],"world_pixels_per_tile":32,"pixels":[1280,800]};var right:Dictionary={"camera_tile":[26.0,47.0],"world_pixels_per_tile":32.0,"pixels":[1280.0,800.0]}
	check(Comparison.same_camera(left,right),"numeric integer/float metadata canonicalized")
	right.world_pixels_per_tile=31;check(not Comparison.same_camera(left,right),"different zoom rejected")
	right.world_pixels_per_tile=32;right.camera_tile[0]=27;check(not Comparison.same_camera(left,right),"different location rejected")
	check(Comparison.same_camera({},right)==false,"missing camera proof rejected")
	var directory:=OS.get_environment("HABITAT_ART_COMPARE_EVIDENCE")
	if not directory.is_empty():
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("comparison-records.json")))
		for record in data.records:
			check(Comparison.same_camera(record.left,record.right),"actual reference and study same camera "+record.study)
			var original:=Image.load_from_file(directory.path_join(record.left.file));original.convert(Image.FORMAT_RGBA8)
			var study:=Image.load_from_file(directory.path_join(record.right.file));study.convert(Image.FORMAT_RGBA8)
			var result:=Image.load_from_file(directory.path_join(record.comparison));result.convert(Image.FORMAT_RGBA8)
			check(result.get_region(Rect2i(0,0,1280,800)).get_data()==original.get_data(),"existing viewport pixels unretouched "+record.study)
			check(result.get_region(Rect2i(1280,0,1280,800)).get_data()==study.get_data(),"new viewport pixels unretouched "+record.study)
	print("Art comparisons: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
