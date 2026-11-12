extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var lib=preload("res://scripts/character_library.gd").new();lib.configure(directory)
	var w:=preload("res://tests/main_island_fixture.gd").world();w.library=lib
	check(w.error.is_empty(),"valid enlarged map "+w.error)
	if not w.error.is_empty():quit(1);return
	w.residents.provision(w);w.director.set_all_enabled(false)
	check(Opening.apply(w,lib).ok,"unchanged showcase rules apply")
	var l:Dictionary=w.catalog.regions.home.layout
	check(w.catalog.regions.home.layout.mainland_size[0]==160 and w.catalog.regions.home.layout.mainland_size[1]==128 and w.catalog.regions.home.size[0]==360 and w.catalog.regions.home.size[1]==330,"160x128 region")
	for plot in l.residential:
		var site:Dictionary=w.objects[plot.site_id]
		check(is_equal_approx(w.point(site).y+w.site_size(site).y/2,float(l.residential_front_y)),"house front aligns "+site.id)
	check(l.art_props.all(func(prop):return prop.kind!="clothesline"),"only clothesline prop removed")
	for i in range(4):
		var a:Dictionary=w.objects[l.residential[i].site_id];var b:Dictionary=w.objects[l.residential[i+1].site_id]
		var gap:float=b.position[0]-w.site_size(b).x/2-1.5-(a.position[0]+w.site_size(a).x/2+1.5)-.6
		check(gap>=3,"three clear tiles between actual yard fence collisions")
		var x:float=(a.position[0]+w.site_size(a).x/2+1.5+b.position[0]-w.site_size(b).x/2-1.5)/2
		var clear:=true
		for step in range(35):
			for dx in [-1.5,0,1.5]:
				if not w.walkable("home",Vector2(x+dx,13+step*.5)):clear=false
		check(clear,"three-wide actual beach passage "+str(i))
	var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree");var minimum:=INF
	for i in range(trees.size()):
		for j in range(i):minimum=minf(minimum,w.point(trees[i]).distance_to(w.point(trees[j])))
	check(trees.size()>=49 and minimum>=3,"at least 49 clustered trees, true minimum three tiles")
	var boxes:Array=[]
	for site in w.leisure.sites.values():
		for box in w.leisure.art(site).recreation.obstacles:boxes.append({"site":site.id,"rect":Rect2(w.point(site)+Vector2(box[0],box[1]),Vector2(box[2],box[3]))})
	var spaced:=true
	for i in range(boxes.size()):
		for j in range(i):
			if boxes[i].site==boxes[j].site:continue
			var a:Rect2=boxes[i].rect;var b:Rect2=boxes[j].rect
			var dx:float=maxf(0,maxf(a.position.x-b.end.x,b.position.x-a.end.x));var dy:float=maxf(0,maxf(a.position.y-b.end.y,b.position.y-a.end.y))
			if Vector2(dx,dy).length()<3:spaced=false
	check(spaced,"all facility collisions separated by at least three tiles")
	for direction in ["north","south","west","east"]:
		var source:Array=w.map_anchor("plaza."+direction);var dest:Array=l.plaza_approaches[direction];var clear:=true
		var a:=Vector2(source[0],source[1]);var b:=Vector2(dest[0],dest[1]);var side:=Vector2(-(b-a).normalized().y,(b-a).normalized().x)
		for step in range(int(a.distance_to(b)*2)+1):
			var at:Vector2=a.move_toward(b,step*.5)
			for offset in [-1.5,0,1.5]:
				if not w.walkable("home",at+side*offset):clear=false
		check(clear,"three-wide direct center approach "+direction)
		check(F.job(w,"human",{"intent":"move","x":source[0],"y":source[1]}) and F.job(w,"human",{"intent":"move","x":dest[0],"y":dest[1]}),"actual cardinal entry route "+direction)
	check(l.reserved_sites.size()==4,"four future plots distinct from sixth house")
	for id in l.reserved_sites:
		var site:Dictionary=w.objects[id];var rect:=Rect2(w.point(site)-w.site_size(site)/2,w.site_size(site));var empty:=true
		for o in w.objects.values():
			if o.id!=id and o.kind in ["tree","chest"] and rect.has_point(w.point(o)):empty=false
		check(w.site_size(site).x>=12 and w.site_size(site).y>=10 and empty and site.stage_index==0,"empty 12x10 stake/rope footprint "+id)
		check(w.can_approach("human",site),"reserved plot genuinely reachable "+id)
	for seat in w.life.seats():check(w.walkable("home",w.point(seat)),"camp seat remains clear")
	check(w.memories.records.is_empty(),"layout/presets create no fictional history")
	print("Home v3 layout: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
