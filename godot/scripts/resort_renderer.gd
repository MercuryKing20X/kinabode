extends RefCounted
## Native-size scenery only. World owns all routes, claims and materials.
static var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/resort-villas.json"))
static var textures:Dictionary={}
static func texture(style:String,night:bool)->Texture2D:
	var key:String=style+("-night" if night else "-day")
	if not textures.has(key):
		var path:String="res://assets/resort-v2/"+key+".png"
		if not FileAccess.file_exists(path):return null
		textures[key]=ImageTexture.create_from_image(Image.load_from_file(path))
	return textures[key]
static func rect(v:Node,at:Vector2,size:Vector2,color:Color)->void:v.draw_rect(Rect2(v.screen(at-size/2),size*32*v.zoom),color)
static func ground(v:Node)->void:
	if v.region_id!="home":return
	var camp:=Vector2(81,185)
	v._surface(preload("res://scripts/home_layout.gd").rectangle(Rect2(66,177,30,20),3),v.textures.sand,Color("e7d0a7"))
	rect(v,camp+Vector2(0,-3),Vector2(11,2),Color("9d7652"));rect(v,camp+Vector2(0,-3),Vector2(10.7,1.7),Color("c5a779"));rect(v,camp,Vector2(5,2),Color("495453"))
	for i in range(8):v.draw_line(v.screen(camp+Vector2(-2+i*.57,-.8)),v.screen(camp+Vector2(-2+i*.57,.8)),Color("c5b8a0"),2*v.zoom)
	for villa in data.villas:
		var at:=Vector2(villa.position[0],villa.position[1])
		if not v.get_viewport_rect().grow(180).intersects(Rect2(v.screen(at-Vector2(20,30)),Vector2(40,60)*32*v.zoom)):continue
		for activity in villa.activities:
			var p:=Vector2(activity.position[0],activity.position[1])
			if activity.kind=="pool":
				rect(v,p,Vector2(activity.size[0]+1,activity.size[1]+1),Color("ece5ce"));rect(v,p,Vector2(activity.size[0]+.4,activity.size[1]+.4),Color("557c80"));rect(v,p,Vector2(activity.size[0],activity.size[1]),Color("6abdc9"))
				for i in range(21):
					var x:float=p.x-10.5+i
					v.draw_line(v.screen(Vector2(x,p.y-7.5)),v.screen(Vector2(x,p.y-7)),Color("aaa894"),v.zoom)
					v.draw_line(v.screen(Vector2(x,p.y+7)),v.screen(Vector2(x,p.y+7.5)),Color("aaa894"),v.zoom)
				for step in 4:rect(v,p+Vector2(7,-6+step*.6),Vector2(4,1),Color("c9e4dd").darkened(step*.09))
				for i in range(12):
					var wave:Vector2=p+Vector2(-8+(i%4)*5.2,-4+floori(i/4)*4+sin(v.clock+i)*.5)
					v.draw_arc(v.screen(wave),(12+fposmod(v.clock*8+i*4,22))*v.zoom,0,PI,12,Color(.86,1,1,.45),2*v.zoom)
			elif activity.kind=="lounge":
				for slot in activity.slots:
					var seat:=Vector2(slot[0],slot[1]);rect(v,seat,Vector2(2.35,1.35),Color("755b44"));rect(v,seat,Vector2(2.15,1.1),Color("f3e7cd"));rect(v,seat-Vector2(.7,0),Vector2(.6,1.1),Color("88afb3"))
			else:
				for slot in activity.slots:
					var seat:Vector2=v.screen(Vector2(slot[0],slot[1]));v.draw_line(seat-Vector2(0,70)*v.zoom,seat,Color("77664b"),2*v.zoom);v.draw_line(seat-Vector2(20,0)*v.zoom,seat+Vector2(20,0)*v.zoom,Color("caae83"),6*v.zoom)
		var gate:=Vector2(villa.gate[0],villa.gate[1])
		for sign in [-1,1]:
			var post:Vector2=v.screen(gate+Vector2(sign*1.4,0))
			v.draw_line(post,post-Vector2(0,45)*v.zoom,Color("8a6848"),5*v.zoom)
			v.draw_circle(post-Vector2(0,43)*v.zoom,12*v.zoom,Color("789456"))
		var pool:Dictionary=data.villas[0].activities.filter(func(a):return a.kind=="pool")[0]
		var parasol:Vector2=v.screen(Vector2(pool.position[0]+12,pool.position[1]+6))
		v.draw_line(parasol,parasol-Vector2(0,65)*v.zoom,Color("947150"),4*v.zoom);v.draw_circle(parasol-Vector2(0,65)*v.zoom,42*v.zoom,Color("eee4c7"));v.draw_arc(parasol-Vector2(0,65)*v.zoom,30*v.zoom,0,PI,20,Color("86a9ae"),12*v.zoom)
		for offset in [Vector2(-12,-2),Vector2(12,-2),Vector2(-11,10),Vector2(11,10),Vector2(-10,-12),Vector2(10,-12),Vector2(-12,5),Vector2(12,5)]:
			var shrub:Vector2=v.screen(at+offset)
			v.draw_circle(shrub,22*v.zoom,Color("56734a"));v.draw_circle(shrub+Vector2(-5,-5)*v.zoom,15*v.zoom,Color("849954"))
			for f in 4:v.draw_circle(shrub+Vector2((f%2)*12-6,(f/2)*10-5)*v.zoom,3*v.zoom,Color("e1b0b5"))
		var palm:Vector2=v.screen(at+Vector2(-13,-10))
		v.draw_line(palm,palm-Vector2(0,125)*v.zoom,Color("8d6a42"),9*v.zoom)
		for n in 7:
			var dir:Vector2=Vector2.from_angle(n*TAU/7)
			v.draw_line(palm-Vector2(0,125)*v.zoom,palm-Vector2(0,125)*v.zoom+dir*65*v.zoom,Color("56794d"),12*v.zoom)
static func draw_entry(v:Node,entry:Dictionary)->bool:
	if entry.get("type")!="resort_villa":return false
	var row:Dictionary=entry.value;var at:=Vector2(row.position[0],row.position[1]);var size:Vector2=Vector2(640,512)*v.zoom
	var box:=Rect2(v.screen(at)-size/2,size)
	if not v.get_viewport_rect().grow(100).intersects(box):return true
	var art:Texture2D=texture(row.style,v.world.days.phase().id=="night")
	if art!=null:v.draw_texture_rect(art,box,false)
	return true
static func hit(v:Node,mouse:Vector2)->String:
	if v.region_id!="home":return ""
	for villa in data.villas:
		for a in villa.activities:
			var size:Vector2=Vector2(a.size[0],a.size[1])*32*v.zoom
			if Rect2(v.screen(Vector2(a.position[0],a.position[1]))-size/2,size).has_point(mouse):return a.id
		if v.screen(Vector2(villa.door[0],villa.door[1])).distance_to(mouse)<48*v.zoom:return villa.id
	return ""
