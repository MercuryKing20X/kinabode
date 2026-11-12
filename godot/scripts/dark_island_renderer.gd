extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Presentation only. No routes, item creation, actor movement or saved state.
var overlay:Node2D
var torch_sheet:Texture2D
var torch_warning_sheet:Texture2D
var hands:Dictionary={}
var textures:Dictionary={}
func ensure_assets()->void:
	if not textures.is_empty():return
	textures["bridge"]=ImageTexture.create_from_image(Image.load_from_file("res://assets/home-v3/boardwalk.png"))
	for name in ["dark-grass","dark-soil","dark-sand","dark-water","tree","mushroom-dim","mushroom-bright","fireflies","fire-off","fire-0","fire-1","fire-2","beacon-off","beacon-0","beacon-1","beacon-2","dock-h","dock-v","boat","torch-planted"]:
		var path:String="res://assets/dark/"+name+".png"
		if FileAccess.file_exists(path):textures[name]=ImageTexture.create_from_image(Image.load_from_file(path))
func asset(v:Node,name:String,at:Vector2,scale:float=1.0,tint:Color=Color.WHITE,canvas:Node2D=null)->void:
	if not textures.has(name):return
	var texture:Texture2D=textures[name];var size:Vector2=texture.get_size()*scale*v.zoom
	var target:Node2D=v if canvas==null else canvas
	target.draw_texture_rect(texture,Rect2(v.screen(at)-size*Vector2(.5,.94),size),false,tint)

func setup(v:Node)->void:
	ensure_assets()
	if is_instance_valid(overlay):return
	overlay=preload("res://scripts/dark_overlay.gd").new();v.add_child(overlay);overlay.configure(v,self)
	if FileAccess.file_exists("res://assets/dark/torch.png"):torch_sheet=ImageTexture.create_from_image(Image.load_from_file("res://assets/dark/torch.png"))
	if FileAccess.file_exists("res://assets/dark/torch-warning.png"):torch_warning_sheet=ImageTexture.create_from_image(Image.load_from_file("res://assets/dark/torch-warning.png"))
	if FileAccess.file_exists("res://content/torch-hands.json"):hands=JSON.parse_string(FileAccess.get_file_as_string("res://content/torch-hands.json"))
func update(v:Node)->void:
	if not is_instance_valid(overlay):setup(v)
	overlay.update()
func p(value:Array)->Vector2:return Vector2(value[0],value[1])
func draw(v:Node)->void:
	ensure_assets()
	var d:RefCounted=v.world.dark
	var viewport:Rect2=v.get_viewport_rect()
	v._surface(PackedVector2Array([v.local_point(Vector2.ZERO),v.local_point(Vector2(viewport.size.x,0)),v.local_point(viewport.size),v.local_point(Vector2(0,viewport.size.y))]),textures.get("dark-water",v.textures.water),Color("9eb7ba"))
	var land:PackedVector2Array=v.world.catalog.polygon(v.world.catalog.regions.dark)
	v._surface(land,textures.get("dark-sand",v.textures.sand),Color("c0b99f"))
	var center:=Vector2(78,67);var inner:=PackedVector2Array()
	for point in land:inner.append(center+(point-center)*.94)
	v._surface(inner,textures.get("dark-grass",v.textures.grass),Color("b8c2a7"))
	for area in d.config.areas:
		v._surface(PackedVector2Array(area.polygon.map(func(a):return p(a))),textures.get("dark-soil",v.textures.soil) if area.id=="grove" else textures.get("dark-grass",v.textures.grass),Color("7d8271") if area.id=="grove" else Color("859584"))
	for path in d.config.paths:
		for index in range(path.size()-1):
			var start:=p(path[index]);var finish:=p(path[index+1]);var direction:Vector2=(finish-start).normalized();var normal:=Vector2(-direction.y,direction.x)
			var strip:=PackedVector2Array([start-normal,start+normal,finish+normal,finish-normal])
			v._surface(strip,textures.get("dark-soil",v.textures.soil),Color("b5aa87"))
	for pond in d.config.ponds:
		var water:=PackedVector2Array(pond.map(func(a):return p(a)))
		v._surface(water,textures.get("dark-water",v.textures.water),Color("a2b8bc"),Vector2(v.clock*.002,0))
		var edge:=PackedVector2Array(pond.map(func(a):return v.screen(p(a))));edge.append(edge[0]);v.draw_polyline(edge,Color("9aab94"),8*v.zoom,true)
	boat(v)
	var entries:Array=[]
	for object in v.world.objects.values():
		if object.region_id=="dark":entries.append({"kind":"object","value":object,"y":object.position[1]})
	for actor in v.world.actors.values():
		if actor.region_id=="dark":entries.append({"kind":"actor","value":actor,"y":actor.position[1]})
	for actor in v.world.actors.values():
		if actor.region_id=="dark":v.fishing_renderer.held_back(v,actor)
	entries.sort_custom(func(a,b):return a.y<b.y)
	for entry in entries:
		var value:Dictionary=entry.value
		if entry.kind=="actor":v._actor(value);continue
		var at:Vector2=v.world.point(value)
		if value.kind=="tree":
			if value.status=="stump":v._sprite("stump",at,.6)
			else:asset(v,"tree",at,.7 if value.status=="sapling" else 2.0,Color("dbe6c9"))
	for patch in d.life.patches.values():
		if patch.amount>0:v._sprite("mushrooms",p(patch.position),.7)
	for drop in v.world.drops.values():
		if drop.region_id=="dark":v._sprite("logs",p(drop.position),.8)
	var station:Dictionary=d.life.station
	var art:Dictionary=station.artwork if not station.artwork.is_empty() else v.library.artworks["camp-grill"]
	v._camp_sprite(art,"cooking" if d.life.fireside.burning() else "cold",p(d.config.camp),"cooking" if d.life.fireside.burning() else "cold")
	for index in range(d.fires.size()):fire(v,p(d.fires[index].position),1.0)
	for area in d.config.areas:
		if area.has("beacon"):asset(v,"beacon-"+str(int(v.clock*6)%3) if area.id in d.beacons else "beacon-off",p(area.beacon),1.25)

	if d.torch.planted and d.torch.remaining>0:asset(v,"torch-planted",p(d.torch.position),.55)
	if d.phase=="ignite" and not d.pending.is_empty() and d.pending.kind in ["fire","beacon"]:
		var from:Vector2=v.screen(p(d.torch.position) if d.torch.planted and d.torch.remaining>0 else v.world.point(v.world.actors.human))+Vector2(0,-36)*v.zoom
		var to:Vector2=v.screen(p(d.pending.position))+Vector2(0,-18)*v.zoom
		var progress:float=clampf(1.0-d.gesture_left/float(d.config.gesture_seconds),0,1)
		for n in range(5):
			var travel:float=clampf(progress-n*.055,0,1)
			v.draw_circle(from.lerp(to,travel),maxf(1,3.5-n*.5)*v.zoom,Color(1,.57+float(n)*.06,.18,.95-float(n)*.12))

func stone()->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color("849193");style.border_color=Color("46575c");style.set_border_width_all(3);style.set_corner_radius_all(5);return style
func fire(v:Node,at:Vector2,size:float)->void:
	asset(v,"fire-"+str(int(v.clock*7+at.x)%3),at,.65*size)
func boat(v:Node)->void:
	if v.world.dark==null or not v.world.dark.enabled() or v.region_id not in ["home","dark"]:return
	ensure_assets()
	var d:RefCounted=v.world.dark
	var shape:Array=d.config.walking_connection.home_bridge if v.region_id=="home" else d.config.walking_connection.dark_bridge
	if v.region_id=="home":
		# Adjacent island is visible across the seam; its unlit terrain stays dark.
		var home:Dictionary=v.world.catalog.regions.home;var other:Dictionary=v.world.catalog.regions.dark
		var offset:Vector2=p(other.origin)-p(home.origin)
		v.draw_colored_polygon(PackedVector2Array(other.land.map(func(a):return v.screen(p(a)+offset))),Color("14232c"))
		v._surface(PackedVector2Array(d.config.walking_connection.dark_bridge.map(func(a):return p(a)+offset)),textures.bridge,Color.WHITE)
		var camp:Vector2=p(d.config.camp)+offset
		v.draw_circle(v.screen(camp),float(d.config.camp_radius)*32*v.zoom,Color("66715a"))
	v._surface(PackedVector2Array(shape.map(func(a):return p(a))),textures.bridge,Color.WHITE)
	if v.region_id=="home":
		v.draw_string(v.font,v.screen(p(d.config.home_dock)+Vector2(0,-3))+Vector2(-65,0),LocalText.text("ui.dark.bridge_sign"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ffe2a4"))
func hit(v:Node,mouse:Vector2)->String:
	if v.world.dark==null or not v.world.dark.enabled():return ""
	var d:RefCounted=v.world.dark
	if v.region_id in ["home","dark"]:
		var at:Vector2=v.screen(p(d.config.home_dock if v.region_id=="home" else d.config.dock))
		if Rect2(at-Vector2(40,80)*v.zoom,Vector2(80,115)*v.zoom).has_point(mouse):return "dark.boat"
	if v.region_id!="dark":return ""
	for item in d.discoveries.config.objects:
		if d.discoveries.eligible(item) and mouse.distance_to(v.screen(p(item.position)))<20*v.zoom:return "relic:"+item.id
	for fly in d.discoveries.fireflies():
		if mouse.distance_to(v.screen(p(fly.position)))<22*v.zoom:return fly.id
	if mouse.distance_to(v.screen(p(d.discoveries.config.star_seat)))<25*v.zoom:return "star-seat"
	for area in d.config.areas:
		if area.has("beacon") and Rect2(v.screen(p(area.beacon))-Vector2(30,85)*v.zoom,Vector2(60,100)*v.zoom).has_point(mouse):return "dark.beacon."+str(area.id)
	for index in range(d.fires.size()):
		if mouse.distance_to(v.screen(p(d.fires[index].position)))<30*v.zoom:return "dark.fire."+str(index)
	if mouse.distance_to(v.screen(p(d.config.camp)))<48*v.zoom:return "dark.barbecue"
	for patch in d.life.patches.values():
		if patch.amount>0 and mouse.distance_to(v.screen(p(patch.position)))<35*v.zoom:return str(patch.id)
	for object in v.world.objects.values():
		if object.region_id!="dark" or object.kind!="tree":continue
		var size:=Vector2(150,200)
		if Rect2(v.screen(p(object.position))-Vector2(size.x*.5,size.y-8)*v.zoom,size*v.zoom).has_point(mouse):return object.id
	for drop in v.world.drops.values():
		if drop.region_id=="dark" and mouse.distance_to(v.screen(p(drop.position)))<30*v.zoom:return drop.id
	return ""
func glows(v:Node,canvas:Node2D)->void:
	var d:RefCounted=v.world.dark
	for glow in d.config.glows:
		var at:Vector2=v.screen(p(glow.position));var pulse:float=.8+sin(v.clock*1.5+float(glow.position[0]))*.15
		if glow.kind=="mushroom":
			asset(v,"mushroom-bright" if int(v.clock*1.2+float(glow.position[0]))%2 else "mushroom-dim",p(glow.position),.42,Color(1,1,1,pulse),canvas)
		else:
			if d.permanent(p(glow.position)):continue
			var drift:=Vector2(sin(v.clock*.7)*.3,cos(v.clock*.9)*.2)
			asset(v,"fireflies",p(glow.position)+drift,.62,Color(1,1,1,pulse),canvas)
	for area in d.config.areas:
		if area.has("beacon") and area.id not in d.beacons:canvas.draw_circle(v.screen(p(area.beacon))+Vector2(0,-73)*v.zoom,3*v.zoom,Color("d78551"))
func discoveries_draw(v:Node,canvas:Node2D)->void:
	var d:RefCounted=v.world.dark
	for item in d.discoveries.config.objects:
		if d.discoveries.eligible(item):asset(v,"mushroom-dim",p(item.position),.35,Color("ffe1a1"),canvas)
	var seat:Vector2=v.screen(p(d.discoveries.config.star_seat));canvas.draw_arc(seat,12*v.zoom,0,TAU,16,Color("889bba"),2)
	if not d.discoveries.seated.is_empty():
		for i in range(48):
			var at:=Vector2(fmod(i*97.0,v.get_viewport_rect().size.x),30+fmod(i*37.0,170))
			canvas.draw_circle(at,1.5,Color(1,1,.9,.3 if d.torch.remaining>0 else .9))
func torch(v:Node,at:Vector2,anchor:Vector2,warning:bool,running:bool,facing:String)->void:
	if torch_sheet==null:return
	var column:int=int(v.clock*(15 if warning else 8))%4
	var size:Vector2=Vector2(32,64)*v.zoom
	var sheet:Texture2D=torch_warning_sheet if warning and torch_warning_sheet!=null else torch_sheet
	v.draw_texture_rect_region(sheet,Rect2(at-anchor*v.zoom,size),Rect2(column*32,0,32,64),Color(1,1,1,.75+sin(v.clock*22)*.2 if warning else 1.0))
	if running:
		var direction:=Vector2.LEFT if facing=="right" else Vector2.RIGHT if facing=="left" else Vector2(0,1 if facing=="up" else -1)
		var tip:Vector2=at+Vector2(0,-40)*v.zoom
		v.draw_colored_polygon(PackedVector2Array([tip+Vector2(-3,4)*v.zoom,tip+direction*(20+sin(v.clock*17)*4)*v.zoom,tip+Vector2(3,-5)*v.zoom]),Color(1,.63,.23,.75))
func held(v:Node,actor:Dictionary,pose:Dictionary,art:Dictionary,front:bool=true)->void:
	if actor.id!="human" or v.region_id!="dark" or not v.world.dark.here():return
	var d:RefCounted=v.world.dark
	if d.torch.remaining<=0 or d.torch.planted:return
	var id:String=v.library.visual_appearance(actor);var table:Dictionary=hands.get("works",{}).get(id,{})
	var hand:Array=[];var running:bool=v.world.display_running(actor.id) and v.world.motion_state(actor.id).moving
	if running and not v.action_atlases.spec("run",v.library,actor).is_empty():
		var row:int=["down","left","right","up"].find(actor.facing)
		hand=table.get("run",[[],[],[],[]])[row][v.motion.run_column(actor.id,v.world.intelligence.gait(actor.id))] if table.has("run") else []
	else:hand=table.get("frames",{}).get(str(pose.frame),table.get("frames",{}).get(actor.facing+"_0",[]))
	if hand.size()!=2:return
	var expected_front:bool=bool(table.get("run_front",[true,true,true,false])[["down","left","right","up"].find(actor.facing)]) if running else bool(table.get("frames_front",{}).get(str(pose.frame),actor.facing!="up"))
	if front!=expected_front:return
	var at:Vector2=(p(hand)-p(art.anchor))*v.zoom
	torch(v,at,Vector2(16,48),d.torch.remaining<=d.config.torch_warning_seconds,running,actor.facing)
