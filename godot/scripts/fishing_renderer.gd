class_name FishingRenderer
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Original authored pixel matrices; no routes, loot or timers are advanced here.
var art: Dictionary={}
var textures: Dictionary={}
var actor_heights: Dictionary={}
var greeted: Dictionary={}
var arms: Dictionary={}
var pose_art: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/fishing-poses.json"))
var animation_manifest:Dictionary={}
var animation_sheets:Dictionary={}
var animation_frames:Dictionary={}
var animation_verified:Dictionary={}
var swimmers:Dictionary={}
var kite_parts:Dictionary={}
func greet(fish_id: String,time: float) -> void:
	greeted[fish_id]=time+2.5
	if greeted.size()>128:greeted.erase(greeted.keys()[0])
func _init() -> void:
	art=JSON.parse_string(FileAccess.get_file_as_string("res://content/fish-art.json"))
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/fishing-animations/manifest.json"))
	if data is Dictionary:animation_manifest=data.get("works",{})

func animation_texture(view:Node,actor:Dictionary)->Texture2D:
	var job:Dictionary=view.world.work.jobs.get(actor.id,{})
	if job.get("intent")!="fish" or job.get("phase") not in ["fish_cast","fish_wait","fish_bite","fish_reel"] or view.world._routes.has(actor.id):return null
	var id:String=view.library.visual_appearance(actor);var spec:Dictionary=animation_manifest.get(id,{})
	if spec.get("status")!="independent":return null
	var work:Dictionary=view.library.artworks.get(id,{})
	var check_key:String=id+":"+str(work.get("revision",0))
	if not animation_verified.has(check_key):
		var values:PackedStringArray=[]
		var layers:Array=work.get("frames",{}).get("down_0",[])
		if layers.size()==1 and layers[0].get("visible",false):
			for value in layers[0].get("pixels",[]):values.append(str(int(value)))
		animation_verified[check_key] = not values.is_empty() and ",".join(values).sha256_text()==str(spec.get("base_frame_sha256","")) and "|".join(PackedStringArray(work.get("palette",[]))).sha256_text()==str(spec.get("base_palette_sha256",""))
	if not animation_verified[check_key]:return null
	var dir:int=["down","left","right","up"].find(str(actor.facing))
	if dir<0:dir=0
	var col:int=animation_column(view,job)
	var tips:Array=spec.get("rod_tips",[])
	if tips.size()!=4 or tips[dir][col]==null:return null
	var key:String=id+":"+str(dir)+":"+str(col)
	if animation_frames.has(key):return animation_frames[key]
	if not animation_sheets.has(id):
		var imported:Texture2D=load("res://content/fishing-animations/"+str(spec.asset))
		if imported==null or imported.get_size()!=Vector2(672,512):return null
		animation_sheets[id]=imported
	var result:=AtlasTexture.new();result.atlas=animation_sheets[id];result.region=Rect2(col*96,dir*128,96,128);animation_frames[key]=result
	return result
func animation_column(view:Node,job:Dictionary)->int:
	var col:int=0
	match str(job.phase):
		"fish_cast":col=mini(2,int(float(job.time)/float(view.world.fishing.rules.cast_seconds)*3))
		"fish_wait":col=3+int(view.clock*1.5)%2
		_:col=5+int(view.clock*3)%2
	return col

func texture(species_id: String,color_id: String,rules: Dictionary,frame:int=-1,purpose:String="card") -> Texture2D:
	if art.get("standard_v3",{}).get("species",{}).has(species_id):return detailed_texture(species_id,color_id,rules,frame,purpose)
	var key:=species_id+":"+color_id
	if textures.has(key):return textures[key]
	var source: Dictionary=art.sprites[species_id]
	var image:=Image.create(int(source.width),int(source.height),false,Image.FORMAT_RGBA8)
	var tint:=Color.WHITE
	for option in rules.colors:
		if option.id==color_id:tint=Color(option.tint)
	for y in range(source.height):
		for x in range(source.width):
			var symbol: String=source.rows[y][x]
			var color:=Color(art.palette[symbol])
			if symbol in ["2","3","4","7"]:
				color=color.lerp(tint,.48 if symbol=="4" else .75)
				if species_id=="glass":color.a=.64
			image.set_pixel(x,y,color)
	var used:=image.get_used_rect()
	image=image.get_region(used)
	textures[key]=ImageTexture.create_from_image(image)
	return textures[key]
func actor_height(view: Node,actor: Dictionary) -> float:
	var id: String=view.library.visual_appearance(actor)
	if not actor_heights.has(id):actor_heights[id]=view.library.texture(id,"down_0").get_image().get_used_rect().size.y
	return float(actor_heights[id])
func fish_length(view: Node,entry: Dictionary) -> float:
	var actor: Dictionary=view.world.actors.get(entry.owner_id,view.world.actors.human)
	return actor_height(view,actor)*float(entry.scale)*view.zoom
func fish_image(view: Node,entry: Dictionary,at: Vector2,alpha:=1.0,flip:=false,display_scale:=1.0,swimming:=false,heading:=0.0) -> void:
	var tex:=texture(entry.species_id,entry.color_id,view.world.fishing.rules,int(view.clock*4)%4 if swimming else -1,"pen" if swimming else "held")
	var length:=fish_length(view,entry)*display_scale
	var size:=Vector2(length,length*tex.get_height()/float(tex.get_width()))
	var wiggle:float=1.0+.035*sin(view.clock*4+float(hash(entry.id)%13)) if swimming else 1.0
	view.draw_set_transform(at,heading if swimming else 0.0,Vector2((1 if swimming else (-1 if flip else 1))*wiggle,1.0/wiggle))
	if swimming and entry.species_id=="kite" and not art.has("standard_v3"):
		var key:String=entry.species_id+":"+entry.color_id
		if not kite_parts.has(key):
			var split:int=int(tex.get_width()*.46)
			var tail:=AtlasTexture.new();tail.atlas=tex;tail.region=Rect2(0,0,split,tex.get_height())
			var body:=AtlasTexture.new();body.atlas=tex;body.region=Rect2(split,0,tex.get_width()-split,tex.get_height())
			kite_parts[key]={"tail":tail,"body":body,"fraction":float(split)/tex.get_width()}
		var part:Dictionary=kite_parts[key];var split_x:float=-size.x/2+size.x*part.fraction
		view.draw_texture_rect(part.body,Rect2(Vector2(split_x,-size.y/2),Vector2(size.x*(1-part.fraction),size.y)),false,Color(1,1,1,alpha))
		var flap:float=sin(view.clock*3+float(hash(entry.id)%13))*.12
		var origin:Vector2=at+Vector2(split_x,0).rotated(heading)
		view.draw_set_transform(origin,heading+flap,Vector2(wiggle,1.0/wiggle))
		view.draw_texture_rect(part.tail,Rect2(Vector2(-size.x*part.fraction,-size.y/2),Vector2(size.x*part.fraction,size.y)),false,Color(1,1,1,alpha))
		view.draw_set_transform(at,heading,Vector2(wiggle,1.0/wiggle))
	else:view.draw_texture_rect(tex,Rect2(-size/2,size),false,Color(1,1,1,alpha))
	if entry.color_id=="aurora":
		for i in range(3):
			var spark:=Vector2(sin(view.clock*.6+i*2)*size.x*.3,cos(view.clock*.8+i*2)*size.y*.3)
			view.draw_line(spark-Vector2(3,0),spark+Vector2(3,0),Color(1,.98,.8,alpha),1)
			view.draw_line(spark-Vector2(0,3),spark+Vector2(0,3),Color(1,.98,.8,alpha),1)
	view.draw_set_transform(Vector2.ZERO)

func pen_display_scale(view:Node,rect:Rect2,fish:Array)->float:
	var largest:=1.0
	for entry in fish:largest=maxf(largest,fish_length(view,entry)/view.zoom)
	return minf(1.0,minf(rect.size.x*32*.72,rect.size.y*32*.72)/largest)

func swim_clearance(point:Vector2,extent:Vector2,pen_id:String,ignore_id:String)->float:
	var nearest:=12.0;var overlap:=0.0;var box:=Rect2(point-extent,extent*2)
	for other_id in swimmers:
		if other_id==ignore_id or swimmers[other_id].get("pen_id")!=pen_id:continue
		var other:Dictionary=swimmers[other_id];var other_box:=Rect2(other.position-other.extent,other.extent*2)
		nearest=minf(nearest,point.distance_to(other.position))
		var intersection:Rect2=box.intersection(other_box)
		if intersection.has_area():overlap+=intersection.get_area()
	return nearest-overlap*3.0

func swim(view:Node,entry:Dictionary,rect:Rect2,display_scale:float)->Dictionary:
	var id:String=entry.id;var tex:=texture(entry.species_id,entry.color_id,view.world.fishing.rules)
	var length:float=fish_length(view,entry)/view.zoom*display_scale/32.0
	# A circular bound contains the whole sprite even while turning diagonally.
	var fish_height:float=length*float(tex.get_height())/float(tex.get_width())
	var radius:float=Vector2(length,fish_height).length()*(.60 if entry.species_id=="kite" else .52)
	var extent:=Vector2(radius,radius)
	var margin:=extent+Vector2(.25,.25)
	var low:Vector2=rect.position+margin;var high:Vector2=rect.end-margin
	if low.x>high.x:low.x=rect.get_center().x;high.x=low.x
	if low.y>high.y:low.y=rect.get_center().y;high.y=low.y
	if not swimmers.has(id) or swimmers[id].get("pen_id")!=entry.location:
		var rng:=RandomNumberGenerator.new();rng.seed=absi(hash(id))+1
		var start:=Vector2(rng.randf_range(low.x,high.x),rng.randf_range(low.y,high.y));var score:float=-INF
		for i in range(20):
			var candidate:=Vector2(rng.randf_range(low.x,high.x),rng.randf_range(low.y,high.y))
			var clearance:float=swim_clearance(candidate,extent,entry.location,id)
			if clearance>score:start=candidate;score=clearance
		var initial_heading:float=rng.randf_range(-PI,PI)
		swimmers[id]={"pen_id":entry.location,"position":start,"target":start,"heading":initial_heading,"facing":initial_heading,"pause":0.0,"last":view.clock,"rng":rng,"flip":false,"extent":extent}
	var state:Dictionary=swimmers[id]
	var delta:float=clampf(view.clock-float(state.last),0,.2);state.last=view.clock;state.extent=extent
	state.position=Vector2(clampf(state.position.x,low.x,high.x),clampf(state.position.y,low.y,high.y))
	if float(state.pause)>0:
		state.pause=maxf(0,float(state.pause)-delta)
	elif state.position.distance_to(state.target)<.25:
		state.pause=state.rng.randf_range(.3,1.2)
		var best:Vector2=state.position;var best_score:float=-INF
		for i in range(6):
			var point:=Vector2(state.rng.randf_range(low.x,high.x),state.rng.randf_range(low.y,high.y))
			var score:float=point.distance_to(state.position)*.1+swim_clearance(point,extent,entry.location,id)
			if score>best_score:best=point;best_score=score
		state.target=best
	else:
		var direction:Vector2=(state.target-state.position).normalized()
		for other_id in swimmers:
			if other_id==id or swimmers[other_id].get("pen_id")!=entry.location:continue
			var other:Dictionary=swimmers[other_id];var away:Vector2=state.position-other.position
			var spacing:float=maxf(1.0,minf(extent.x+other.extent.x,extent.y+other.extent.y)*1.4)
			if away.length()>.001 and away.length()<spacing:direction+=away.normalized()*(spacing-away.length())/spacing*1.8
		var desired:float=direction.angle();state.heading=lerp_angle(float(state.heading),desired,clampf(delta*2.2,0,1))
		var velocity:=Vector2.from_angle(float(state.heading))*(.9/(1.0+float(entry.scale)*.25))
		var before:Vector2=state.position
		var next:Vector2=before+velocity*delta
		state.position=Vector2(clampf(next.x,low.x,high.x),clampf(next.y,low.y,high.y))
		var displacement:Vector2=state.position-before
		if displacement.length_squared()>0.0:state.facing=displacement.angle()
		if displacement.x!=0.0:state.flip=displacement.x<0
	return state
func water(view: Node) -> void:
	if swimmers.size()>view.world.fishing.fish.size():
		for id in swimmers.keys():
			if not view.world.fishing.fish.has(id) or not view.world.fishing.pens.has(view.world.fishing.fish[id].location):swimmers.erase(id)
	for pen in view.world.fishing.pens.values():
		if not view.world.standard.ready(pen.id):continue
		if pen.region_id!=view.region_id:continue
		var rect: Rect2=view.world.catalog.rectangle(pen.rect)
		var screen_rect:=Rect2(view.screen(rect.position),rect.size*32*view.zoom)
		if not view.get_viewport_rect().grow(200).intersects(screen_rect):continue
		view.draw_rect(screen_rect,Color(.10,.29,.34,.25))
		if view.world.locations.v3():
			for n in range(6):
				var at:Vector2=rect.position+rect.size*Vector2((n+.5)/6.0,.12 if n%2==0 else .88)
				var p:Vector2=view.screen(at)
				view.draw_rect(Rect2(p-Vector2(2,3)*view.zoom,Vector2(4,6)*view.zoom),Color("e1bc77"))
		# Rope/net perimeter uses existing authored fence assets, never land collision.
		var corners: Array[Vector2]=[rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y),rect.position]
		for i in range(4):
			var a: Vector2=view.screen(corners[i]);var b: Vector2=view.screen(corners[i+1])
			view.draw_line(a,b,Color("dfc997"),maxf(1,3*view.zoom),true)
			view.draw_line(a+Vector2(0,5)*view.zoom,b+Vector2(0,5)*view.zoom,Color(.2,.37,.38,.55),maxf(1,2*view.zoom),true)
			var steps:=maxi(1,int(corners[i].distance_to(corners[i+1])/4))
			for n in range(steps):
				var at: Vector2=corners[i].lerp(corners[i+1],float(n)/steps)
				view._sprite("barrel",at,.14,Color("d9c9a8"))
		if view.world.locations.v3():
			# Visible hanging net, posts and rope attached to the authored water enclosure.
			for i in range(4):
				var start:Vector2=view.screen(corners[i]);var finish:Vector2=view.screen(corners[i+1])
				var count:int=maxi(1,int(corners[i].distance_to(corners[i+1])*2))
				for n in range(count+1):
					var p:Vector2=start.lerp(finish,float(n)/count)
					view.draw_line(p,p+Vector2(0,13)*view.zoom,Color("76978b"),maxf(1,view.zoom))
				view.draw_line(start+Vector2(0,13)*view.zoom,finish+Vector2(0,13)*view.zoom,Color("849c88"),maxf(1,view.zoom))
		var fishes: Array=view.world.fishing.residents_fish(pen.id)
		fishes.sort_custom(func(a,b):return a.scale>b.scale)
		var fit:float=pen_display_scale(view,rect,fishes)
		for index in range(fishes.size()):
			var entry: Dictionary=fishes[index];var state:Dictionary=swim(view,entry,rect,fit);var p:Vector2=state.position
			var reaction: float=maxf(0,float(greeted.get(entry.id,0))-view.clock)/2.5
			p.y-=sin(reaction*PI)*1.2
			if reaction>0:view.draw_arc(view.screen(p),45*view.zoom,0,TAU,24,Color(1,.92,.7,reaction*.6),2*view.zoom,true)
			fish_image(view,entry,view.screen(p),.78,bool(state.flip),fit,true,float(state.facing))
			if entry.species_id in ["lantern","star","moonfish","angler"]:
				view.draw_arc(view.screen(p),30*view.zoom,0,TAU,24,Color(.9,.9,.6,.15),6*view.zoom,true)
		if view.has_method("map_label"):
			view.map_label(pen.name,rect.position+Vector2(rect.size.x*.25,-.35));continue
		var label_size:int=maxi(8,int(14*view.zoom)) if view.world.locations.v3() else 16
		view.draw_string_outline(view.font,screen_rect.position+Vector2(8,-6)*view.zoom,LocalText.content(str(pen.name)),HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,2 if view.world.locations.v3() else 4,Color("254d52"))
		view.draw_string(view.font,screen_rect.position+Vector2(8,-6)*view.zoom,LocalText.content(str(pen.name)),HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,Color("fff0c7"))

func overlay(view: Node) -> void:
	for effect in view.effects:
		if effect.kind=="fish_caught_shadow" and effect.region_id==view.region_id and effect.has("fish"):
			var age:float=clampf((view.clock-float(effect.started))/.8,0,1)
			var entry:Dictionary=effect.fish
			if view.world.fishing.fish.has(entry.id):fish_image(view,entry,view.screen(Vector2(effect.position[0],effect.position[1])),.4*(1-age),false,.35,true,0)
		if effect.kind in ["fish_splash","fish_nibble","fish_bite"] and effect.region_id==view.region_id:
			var age: float=clampf((view.clock-float(effect.started))/.8,0,1)
			var at: Vector2=view.screen(Vector2(effect.position[0],effect.position[1]))
			view.draw_arc(at,(9+age*34)*view.zoom,0,TAU,28,Color(.85,1,1,(1-age)*.75),2*view.zoom,true)
			if effect.kind=="fish_splash":
				for drop in range(5):
					var offset: Vector2=Vector2((drop-2)*14*age,-sin(age*PI)*26)*view.zoom
					view.draw_rect(Rect2(at+offset,Vector2(3,5)*view.zoom),Color(.9,1,1,1-age))
		if effect.kind!="fish_release" or not effect.has("fish") or effect.region_id!=view.region_id:continue
		var age: float=clampf((view.clock-float(effect.started))/.8,0,1)
		var at: Vector2=view.screen(Vector2(effect.position[0],effect.position[1]))
		fish_image(view,effect.fish,at+Vector2(age*30,age*15)*view.zoom,1-age)
		view.draw_arc(at,(15+age*55)*view.zoom,0,TAU,24,Color(.9,1,1,.6*(1-age)),2*view.zoom,true)
# Default remains the procedural rod API; rendered atlas lines explicitly opt
# into authored_pose with the exact body transform from IslandView.
func rod_geometry(view: Node,actor: Dictionary,pose:Dictionary={},authored_pose:bool=false) -> Dictionary:
	var job: Dictionary=view.world.work.jobs.get(actor.id,{})
	if job.get("intent")!="fish" or job.phase=="fish_approach" or view.world._routes.has(actor.id):return {}
	var scale: float=actor_height(view,actor)/80.0*view.zoom
	var at: Vector2=view.screen(view.world.point(actor))
	var facing: String=actor.facing
	var grips: Dictionary=pose_art.rod_grips.get(facing,pose_art.rod_grips.down)
	var hand: Vector2=at+Vector2(grips.hands[1][0],grips.hands[1][1])*scale
	var target: Vector2=view.screen(Vector2(job.hook[0],job.hook[1]))
	var normal: Vector2=(target-at).normalized()
	var vector: Vector2=(normal*70+Vector2(22 if absf(normal.x)<.4 else 0,-85)).normalized()*105*scale
	var progress: float=float(job.time)/float(view.world.fishing.rules.cast_seconds) if job.phase=="fish_cast" else 1.0
	if job.phase=="fish_cast":hand+=Vector2(0,-sin(clampf(progress,0,1)*PI)*9)*scale
	if job.phase=="fish_cast":
		var swing: float=sin(clampf(progress/.4,0,1)*PI/2)
		if progress<.4:vector=(-normal*65+Vector2(0,-105)).normalized()*105*scale;vector=vector.rotated((swing-.5)*.25)
		else:vector=vector.rotated(sin(clampf((progress-.4)/.6,0,1)*PI)*.2)
	var pull:=0.0
	if job.phase in ["fish_bite","fish_reel"]:pull=(.5+sin(view.clock*8+hash(actor.id)%7)*.5)*14*scale
	var tip: Vector2=hand+vector+Vector2(0,pull)
	if authored_pose:
		var spec:Dictionary=animation_manifest[view.library.visual_appearance(actor)]
		var row:int=["down","left","right","up"].find(str(actor.facing))
		var pixel:Array=spec.rod_tips[maxi(0,row)][animation_column(view,job)]
		var work:Dictionary=view.library.artworks[view.library.visual_appearance(actor)]
		var local:Vector2=(Vector2(pixel[0]+.5,pixel[1]+.5)-Vector2(work.anchor[0],work.anchor[1]))*view.zoom
		local*=Vector2(pose.get("scale",Vector2.ONE))
		tip=at+Vector2(float(pose.get("sway",0)),float(pose.get("bob",0)))*view.zoom+local.rotated(float(pose.get("lean",0)))
		# The rod is painted in the atlas: keep the line attached even on a pull.
		# Pull tension changes the line curve, never invents a displaced rod tip.
	var hook:=target
	if job.phase=="fish_cast":
		var flight: float=clampf((progress-.35)/.55,0,1)
		hook=tip.lerp(target,flight)+Vector2(0,-sin(flight*PI)*85*scale)
	elif job.phase=="fish_reel":
		var retrieve: float=clampf(float(job.time)/float(view.world.fishing.rules.reel_seconds),0,1)
		hook=target.lerp(at+normal*45*scale,retrieve*.88)
	var recent: Dictionary=view.world.fishing.life.presentation(actor.id)
	var nibble: bool=recent.get("kind")=="nibble" and job.phase=="fish_wait"
	var bob: float=sin(view.clock*(12 if nibble or job.phase=="fish_bite" else 2.4))*(6 if nibble or job.phase=="fish_bite" else 1.8)*scale
	return {"at":at,"hand":hand,"tip":tip,"hook":hook+Vector2(0,bob),"target":target,"normal":normal,"scale":scale,"grips":grips,"phase":job.phase,"progress":progress,"pull":pull}
func rod_pose(view: Node,actor: Dictionary,pose: Dictionary) -> void:
	var job: Dictionary=view.world.work.jobs.get(actor.id,{})
	if job.get("intent")=="fish" and job.phase!="fish_approach":
		var phase: String=job.phase
		if not view.library.artworks[view.library.visual_appearance(actor)].frames.has(pose.frame):pose.fallback=actor.facing+"_0"
		var side: float=-1 if actor.facing=="left" else 1
		if phase=="fish_cast":pose.lean=side*sin(float(job.time)/float(view.world.fishing.rules.cast_seconds)*TAU)*.13
		elif phase in ["fish_bite","fish_reel"]:
			pose.lean=-side*(.07+sin(view.clock*7)*.035);pose.bob=-absf(sin(view.clock*5))*1.8;pose.scale=Vector2(1.03,.97)
		else:pose.scale=Vector2(1,1+sin(view.clock*2)*.009)
	var reaction: Dictionary=view.world.fishing.life.presentation(actor.id)
	if reaction.is_empty():return
	if reaction.kind in ["catch","giant"]:pose.bob-=absf(sin((view.world.fishing.life.time-reaction.started)*3.5))*3
	if reaction.kind=="admire" and (job.is_empty() or job.get("phase")=="fish_wait"):
		var target: Dictionary=view.world.actors.get(reaction.target_id,{})
		if not target.is_empty():pose.frame=view.motion.direction(view.world.point(target)-view.world.point(actor))+"_0"
		pose.lean=sin(view.clock*4)*.025
	elif reaction.kind=="look":pose.lean=sin(view.clock*2.2)*.035
func _grip_texture(view: Node,actor: Dictionary) -> Texture2D:
	_arm_texture(view,actor)
	var key: String=actor.appearance_id+"grip"
	if arms.has(key):return arms[key]
	var skin: Color=arms.get(actor.appearance_id+"skin",Color("f4c5a5"))
	var palette: Dictionary={".":Color.TRANSPARENT,"o":skin.darkened(.4),"s":skin,"l":skin.lightened(.12),"c":arms.get(actor.appearance_id+"cuff",Color("fff1dc"))}
	var rows: Array=pose_art.grip_arm
	var bitmap:=Image.create(8,rows.size(),false,Image.FORMAT_RGBA8)
	for y in range(rows.size()):
		for x in range(8):bitmap.set_pixel(x,y,palette[rows[y][x]])
	arms[key]=ImageTexture.create_from_image(bitmap);return arms[key]
func rod_front(view: Node,actor: Dictionary,authored_pose:=false,pose:Dictionary={}) -> void:
	var geometry:=rod_geometry(view,actor,pose,authored_pose)
	if geometry.is_empty():return
	var scale: float=geometry.scale
	if not authored_pose:
		var texture:=_grip_texture(view,actor)
		for index in range(2):
			var shoulder: Vector2=geometry.at+Vector2(geometry.grips.shoulders[index][0],geometry.grips.shoulders[index][1])*scale
			var hand: Vector2=geometry.hand+Vector2(-8 if index==0 else 0,4 if index==0 else 0)*scale
			view.draw_set_transform(shoulder,(hand-shoulder).angle()+PI/2)
			view.draw_texture_rect(texture,Rect2(Vector2(-4*scale,-shoulder.distance_to(hand)),Vector2(8*scale,shoulder.distance_to(hand))),false)
		view.draw_set_transform(Vector2.ZERO)
		var bend: Vector2=geometry.hand.lerp(geometry.tip,.55)+geometry.normal*geometry.pull
		var points:=PackedVector2Array()
		for step in range(13):
			var t: float=step/12.0
			points.append((1-t)*(1-t)*geometry.hand+2*(1-t)*t*bend+t*t*geometry.tip)
		view.draw_polyline(points,Color("634f40"),maxf(2,5*scale),true)
		view.draw_polyline(points,Color("c69b69"),maxf(1,2*scale),true)
	var line:=PackedVector2Array()
	for step in range(13):
		var t: float=step/12.0
		line.append(geometry.tip.lerp(geometry.hook,t)+Vector2(0,sin(t*PI)*(4 if geometry.phase in ["fish_bite","fish_reel"] else 16)*scale))
	view.draw_polyline(line,Color(.97,.96,.86,.85),maxf(1,scale),true)
	if geometry.phase!="fish_cast" or geometry.progress>.85:
		view.draw_arc(geometry.hook,12*scale,0,TAU,24,Color(.9,1,1,.45),1,true)
	view.draw_line(geometry.hook-Vector2(0,11)*scale,geometry.hook+Vector2(0,3)*scale,Color("f2b48f"),maxf(2,5*scale),true)
	view.draw_line(geometry.hook-Vector2(0,11)*scale,geometry.hook-Vector2(0,4)*scale,Color("fff2d9"),maxf(2,5*scale),true)
func held_fish(view: Node,actor_id: String) -> Dictionary:
	return view.world.fishing.held(actor_id)
func hold_geometry(view: Node,actor: Dictionary) -> Dictionary:
	var entry: Dictionary=held_fish(view,actor.id)
	if entry.is_empty():return {}
	var tex:=texture(entry.species_id,entry.color_id,view.world.fishing.rules)
	var length:=fish_length(view,entry)
	var display_scale:=1.0
	if entry.species_id in ["noodle","eel","kite","cutlass"]:
		var screen_x:float=view.screen(view.world.point(actor)).x
		var width:float=view.get_viewport_rect().size.x
		var available:float=maxf(32.0,minf(width*.72,2.0*minf(screen_x,width-screen_x)-16.0))
		display_scale=minf(1.0,available/length);length*=display_scale
	var size:=Vector2(length,length*tex.get_height()/float(tex.get_width()))
	var hand: Vector2=view.screen(view.world.point(actor))+Vector2(0,-actor_height(view,actor)*.86)*view.zoom
	var state: Dictionary=view.motion.states.get(actor.id,{})
	if actor.activity=="walking":hand.y-=absf(sin(float(state.get("step",0))*8*PI))*1.4*view.zoom
	var reaction: Dictionary=view.world.fishing.life.presentation(actor.id)
	if reaction.get("kind") in ["catch","giant"]:hand.y-=absf(sin((view.world.fishing.life.time-reaction.started)*3.5))*3*view.zoom
	return {"hand":hand,"center":hand-Vector2(0,size.y/2-3*view.zoom),"size":size,"fish_id":entry.id,"display_scale":display_scale}
func held_back(view: Node,actor: Dictionary) -> void:
	var geometry:=hold_geometry(view,actor)
	if geometry.is_empty():return
	var entry: Dictionary=held_fish(view,actor.id)
	# Keep exact scale; character and arms draw in front, never hidden by the fish.
	fish_image(view,entry,geometry.center,.86 if entry.scale>=4 else 1.0,actor.facing=="left",geometry.display_scale)
func _arm_texture(view: Node,actor: Dictionary) -> Texture2D:
	var id: String=view.library.visual_appearance(actor)
	if arms.has(id):return arms[id]
	var art: Dictionary=view.library.artworks[id]
	var closest:=Color("f4c5a5");var distance:=INF
	for value in art.palette:
		var color:=Color(value)
		if color.a<.5:continue
		var d: float=Vector3(color.r-closest.r,color.g-closest.g,color.b-closest.b).length_squared()
		if d<distance:distance=d;arms[id+"skin"]=color
	var skin: Color=arms.get(id+"skin",closest)
	var base: Image=view.library.texture(id,"down_0").get_image()
	var cuff: Color=base.get_pixel(clampi(int(art.anchor[0]),0,base.get_width()-1),clampi(int(art.anchor[1]-30),0,base.get_height()-1))
	if cuff.a<.5:cuff=Color("fff1dc")
	arms[id+"cuff"]=cuff
	var palette: Dictionary={".":Color.TRANSPARENT,"o":skin.darkened(.4),"s":skin,"l":skin.lightened(.12),"c":cuff}
	var rows: Array=pose_art.left_arm
	var image:=Image.create(12,rows.size(),false,Image.FORMAT_RGBA8)
	for y in range(rows.size()):
		for x in range(12):image.set_pixel(x,y,palette[rows[y][x]])
	arms[id]=ImageTexture.create_from_image(image)
	return arms[id]
func held_front(view: Node,actor: Dictionary) -> void:
	var geometry:=hold_geometry(view,actor)
	if geometry.is_empty():return
	var texture:=_arm_texture(view,actor)
	var scale: float=actor_height(view,actor)/80.0*view.zoom
	var point: Vector2=view.screen(view.world.point(actor))
	var bob: float=geometry.hand.y-(point.y-actor_height(view,actor)*.86*view.zoom)
	for side in [-1,1]:
		view.draw_set_transform(point+Vector2(side*25*scale,bob),0,Vector2(-side,1))
		view.draw_texture_rect(texture,Rect2(Vector2(-6,-67)*scale,Vector2(12,texture.get_height())*scale),false)
	view.draw_set_transform(Vector2.ZERO)
func hit(view: Node,mouse: Vector2) -> String:
	var local: Vector2=view.local_point(mouse)
	for pen in view.world.fishing.pens.values():
		if not view.world.standard.ready(pen.id):continue
		if view.world.catalog.rectangle(pen.rect).has_point(local):
			for entry in view.world.fishing.residents_fish(pen.id):
				var state:Dictionary=swimmers.get(entry.id,{})
				if not state.is_empty() and Rect2(state.position-state.extent,state.extent*2).has_point(local):return "fish:"+str(entry.id)
			return pen.id
	return ""

func gesture_front(view: Node,actor: Dictionary) -> void:
	if actor.activity not in ["gesture_wave","gesture_stretch"]:return
	var texture:=_arm_texture(view,actor)
	var scale: float=actor_height(view,actor)/80.0*view.zoom
	var point: Vector2=view.screen(view.world.point(actor))
	for side in ([-1,1] if actor.activity=="gesture_stretch" else [1]):
		view.draw_set_transform(point+Vector2(side*25*scale,0),sin(view.clock*8)*.1 if actor.activity=="gesture_wave" else 0,Vector2(-side,1))
		view.draw_texture_rect(texture,Rect2(Vector2(-6,-67)*scale,Vector2(12,texture.get_height())*scale),false)
	view.draw_set_transform(Vector2.ZERO)

func detailed_texture(species:String,color_id:String,rules:Dictionary,frame:int,purpose:String)->Texture2D:
	var key:String="v3:"+species+":"+color_id+":"+str(frame)+":"+purpose
	if textures.has(key):return textures[key]
	var spec:Dictionary=art.standard_v3.species[species]
	var filename:String=spec.atlas if frame>=0 else spec.get(purpose,spec.card)
	var source:Image=Image.load_from_file("res://content/fish-v3/"+filename)
	if frame>=0:source=source.get_region(Rect2i(posmod(frame,4)*128,64 if purpose=="pen" else 0,128,64))
	var rect:Array=spec.get("rect",[0,0,128,64])
	source=source.get_region(Rect2i(rect[0],rect[1],rect[2],rect[3]))
	var tint:=Color.WHITE
	for option in rules.colors:
		if option.id==color_id:tint=Color(option.tint)
	for y in source.get_height():
		for x in source.get_width():
			var pixel:Color=source.get_pixel(x,y)
			if pixel.a>0 and color_id!="cream":
				var shaded:Color=pixel.lerp(tint,.22);shaded.a=pixel.a;source.set_pixel(x,y,shaded)
	textures[key]=ImageTexture.create_from_image(source)
	return textures[key]
