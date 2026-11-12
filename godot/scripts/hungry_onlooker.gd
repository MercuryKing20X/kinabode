extends RefCounted
## Read-only presentation over existing follow routes and true fire-eating jobs.
const DEFAULTS={"version":1,"radius":8.0,"seat_margin":0.6,"swallow_every":6.0,"swallow_seconds":0.6,"swallow_pixels":1.5,"drool_every":12.0,"drool_seconds":3.0}
var config:Dictionary=DEFAULTS.duplicate(true)
var mouth_cache:Dictionary={}

func _init()->void:
	var path:="res://content/hungry-onlooker.json"
	if not FileAccess.file_exists(path):return
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	config=value if valid_config(value) else {}

static func valid_config(value:Variant)->bool:
	if not value is Dictionary or value.size()!=DEFAULTS.size() or not value.has_all(DEFAULTS.keys()) or value.version!=1:return false
	for key in DEFAULTS:
		if not (value[key] is int or value[key] is float) or not is_finite(value[key]):return false
	return value.radius>=4 and value.radius<=12 and value.seat_margin>=0.3 and value.seat_margin<=2 and value.swallow_every>=3 and value.swallow_every<=60 and value.swallow_seconds>=0.2 and value.swallow_seconds<=1.5 and value.swallow_seconds<value.swallow_every and value.swallow_pixels>=0.5 and value.swallow_pixels<=3 and value.drool_every>=6 and value.drool_every<=120 and value.drool_seconds>=0.5 and value.drool_seconds<=4 and value.drool_seconds<value.drool_every

func presentation(world:RefCounted,id:String,clock:float)->Dictionary:
	if config.is_empty():return {}
	if id=="human" or not world.actors.has(id) or world.hunger==null or world.hunger.rank(id)<2:return {}
	var actor:Dictionary=world.actors[id];var movement:Dictionary=world.motion_state(id)
	if movement.get("moving",false) or float(movement.get("still_seconds",0))<0.3 or world._routes.has(id) or world.work.jobs.has(id):return {}
	if actor.activity not in ["idle","local_look"] or not world.hunger.can_follow(id):return {}
	var routine:RefCounted=world.director.routines.get(id)
	if routine==null or not routine.chatter or routine.blocked() or routine.time<routine.visual_quiet_until or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return {}
	var best:RefCounted=null;var best_distance:float=float(config.radius)
	for life in world.barbecues.values():
		var fire:RefCounted=life.fireside
		if not fire.burning() or actor.region_id!=life.station.region_id or id in fire.state.get("invited",[]):continue
		# A ready meal is not evidence that someone is actually eating it.
		var eating:=false
		for eater in fire.jobs:
			var job:Dictionary=world.work.jobs.get(eater,{})
			if job.get("id")==fire.jobs[eater] and job.get("target_id")==life.station.id and job.get("phase")=="fire_eat":eating=true;break
		if not eating:continue
		var center:Vector2=world.point(life.station);var distance:float=world.point(actor).distance_to(center)
		var ring:=0.0
		for offset in fire.config.seat_offsets:ring=maxf(ring,Vector2(offset[0],offset[1]).length())
		# Never move a resident to manufacture this pose. Existing follow owns the spot.
		if distance<ring+float(config.seat_margin) or distance>best_distance:continue
		var clear:=true
		for seat in life.seats():
			if world.point(actor).distance_to(world.point(seat))<float(config.seat_margin):clear=false;break
		if not clear:continue
		best=life;best_distance=distance
	if best==null:return {}
	var direction:Vector2=world.point(best.station)-world.point(actor)
	var facing:String=("right" if direction.x>0 else "left") if absf(direction.x)>absf(direction.y) else ("down" if direction.y>0 else "up")
	var offset:float=float(posmod(id.hash(),997))/997.0
	var swallow_phase:float=fposmod(clock+offset*float(config.swallow_every),float(config.swallow_every))
	var swallow:float=sin(PI*swallow_phase/float(config.swallow_seconds)) if swallow_phase<float(config.swallow_seconds) else 0.0
	var drool:bool=fposmod(clock+offset*float(config.drool_every),float(config.drool_every))<float(config.drool_seconds)
	return {"station_id":best.station.id,"facing":facing,"nod":swallow*float(config.swallow_pixels),"drool":drool,"rank":world.hunger.rank(id)}

func apply(pose:Dictionary,cue:Dictionary)->void:
	if cue.is_empty():return
	pose.facing=cue.facing;pose.frame=str(cue.facing)+"_0";pose.fallback=pose.frame
	pose.bob=float(pose.bob)+float(cue.nod);pose.scale.y*=1.0-float(cue.nod)/128.0

func draw_front(view:Node2D,cue:Dictionary,art:Dictionary)->void:
	if cue.is_empty() or not cue.drool or cue.facing=="up":return
	# Tiny independent pixels, under the same body transform. Never edit artwork.
	var scale:float=view.zoom;var mouth:Vector2=mouth_point(art,str(cue.facing))
	if not mouth.is_finite():return
	view.draw_rect(Rect2((mouth+Vector2(0,1))*scale,Vector2(2,3)*scale),Color("b2e2ef"))
	view.draw_rect(Rect2((mouth+Vector2(0,1))*scale,Vector2.ONE*scale),Color("eefbff"))

func mouth_point(art:Dictionary,facing:String)->Vector2:
	var key:String=str(art.id)+":"+str(art.revision)+":"+facing
	if mouth_cache.has(key):return mouth_cache[key]
	# Detect the largest warm skin patch in this frame's face band. This adapts
	# to the current editable face instead of putting a drop on a fixed shirt.
	var width:int=int(art.width);var height:int=int(art.height);var composite:Dictionary={}
	for layer in art.frames.get(facing+"_0",[]):
		if not layer.get("visible",true):continue
		for index in range(layer.pixels.size()):
			var x:int=index%width;var y:int=index/width
			if x<width*.18 or x>width*.82 or y<height*.18 or y>height*.70:continue
			var color:=Color(str(art.palette[int(layer.pixels[index])]))
			if color.a>0.5:composite[index]=color
	var candidates:Dictionary={}
	for index in composite:
		var color:Color=composite[index]
		if color.r>0.55 and color.r-color.g>.018 and color.g>=color.b-.012 and color.s>=.035 and color.s<=.42:candidates[index]=true
	var best:Array=[]
	while not candidates.is_empty():
		var component:Array=[];var stack:Array=[candidates.keys()[0]];candidates.erase(stack[0])
		while not stack.is_empty():
			var index:int=stack.pop_back();component.append(index)
			for neighbor in [index-width,index+width,index-1,index+1]:
				if candidates.has(neighbor) and absi(neighbor%width-index%width)<=1:candidates.erase(neighbor);stack.append(neighbor)
		if component.size()>best.size():best=component
	var point:=Vector2.INF
	if best.size()>=8:
		var low_x:=width;var high_x:=0;var low_y:=height;var high_y:=0
		for index in best:low_x=mini(low_x,index%width);high_x=maxi(high_x,index%width);low_y=mini(low_y,index/width);high_y=maxi(high_y,index/width)
		var x:float=low_x+2 if facing=="left" else high_x-2 if facing=="right" else (low_x+high_x)*.5+2
		point=Vector2(roundf(x),high_y-maxi(2,int((high_y-low_y)*.12)))-Vector2(art.anchor[0],art.anchor[1])
	if mouth_cache.size()>128:mouth_cache.clear()
	mouth_cache[key]=point;return point
