extends RefCounted
## Pure presentation: separate RNG, DayCycle projection, no World writes or saved fields.
const Motion=preload("res://scripts/environment_motion.gd")
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/ambience.json"))
var rng:=RandomNumberGenerator.new()
var waves:Array=[]
var particles:Dictionary={}
var houses:Array=[]
var window_cache:Dictionary={}
var next_house_refresh:=-1.0
var wave_builds:=0
var reference_glass:Image
var window_pixel_counts:Dictionary={}
var lamp_glass:Texture2D
func sample(world:RefCounted)->Dictionary:
	var phases:Array=world.days.config.phases;var fraction:float=world.days.within_day()/world.days.day_seconds
	var index:=0
	for i in range(phases.size()):
		if fraction>=float(phases[i].start):index=i
	var current:Dictionary=config.phases[phases[index].id];var following:Dictionary=config.phases[phases[(index+1)%phases.size()].id]
	var end:float=float(phases[index+1].start) if index+1<phases.size() else 1.0
	var transition:float=minf(float(config.transition_seconds), (end-float(phases[index].start))*world.days.day_seconds)
	var blend:float=smoothstep(0,1,clampf(1-(end-fraction)*world.days.day_seconds/transition,0,1))
	return {"tint":Color(current.tint).lerp(Color(following.tint),blend),"light":lerpf(current.light,following.light,blend),"mist":lerpf(current.mist,following.mist,blend)}
func prepare(view:Node2D)->void:
	rng.seed=int(config.seed);waves.clear();particles.clear()
	var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/works/cottage.json"))
	reference_glass=view.library.render(original,"stage_4")
	var lamp_image:Image=view.props.textures.lamp.get_image();var lamp_mask:=Image.create(lamp_image.get_width(),lamp_image.get_height(),false,Image.FORMAT_RGBA8);lamp_mask.fill(Color.TRANSPARENT)
	for pane in config.lamp_glass_rects:
		for y in range(int(pane[1]),int(pane[1]+pane[3])):
			for x in range(int(pane[0]),int(pane[0]+pane[2])):
				if lamp_image.get_pixel(x,y).a>.5:lamp_mask.set_pixel(x,y,Color(config.warm_light))
	lamp_glass=ImageTexture.create_from_image(lamp_mask)
	var land:PackedVector2Array=view.world.catalog.polygon(view.world.catalog.regions.home)
	for i in range(int(config.limits.coast_waves)):
		var edge:int=i%land.size();var a:Vector2=land[edge];var b:Vector2=land[(edge+1)%land.size()]
		waves.append({"point":a.lerp(b,rng.randf_range(.08,.92)),"normal":Vector2((b-a).normalized().y,-(b-a).normalized().x),"phase":rng.randf()*TAU,"dock":false})
	for extension in view.world.catalog.regions.home.get("land_extensions",[]):
		var contour:PackedVector2Array=preload("res://scripts/home_layout.gd").points(extension)
		for i in range(24):
			var edge:int=i%contour.size();var a:Vector2=contour[edge];var b:Vector2=contour[(edge+1)%contour.size()]
			waves.append({"point":a.lerp(b,.5),"normal":Vector2((b-a).normalized().y,-(b-a).normalized().x),"phase":rng.randf()*TAU,"dock":false})
	# Extensions share the original coast-wave budget; extra land must not
	# multiply the frozen particle limit (64 coast + up to16 dock waves).
	var extensions:int=view.world.catalog.regions.home.get("land_extensions",[]).size()
	if extensions>0:waves=waves.slice(mini(waves.size(),24*extensions))
	waves=waves.slice(0,int(config.limits.coast_waves))
	var docks:Array=view.world.catalog.regions.home.layout.dock_surfaces
	for i in range(int(config.limits.dock_waves)):
		var dock:Dictionary=docks[i%docks.size()];var polygon:PackedVector2Array=preload("res://scripts/home_layout.gd").points(dock.polygon)
		var edge:int=i%4;var a:Vector2=polygon[edge];var b:Vector2=polygon[(edge+1)%4]
		var point:Vector2=a.lerp(b,rng.randf_range(.1,.9));var normal:=Vector2((b-a).normalized().y,-(b-a).normalized().x)
		if not Geometry2D.is_point_in_polygon(point+normal*.4,land):waves.append({"point":point,"normal":normal,"phase":rng.randf()*TAU,"dock":true})
	for kind in ["birds","butterflies","fireflies"]:
		var key:String={"birds":"bird_anchors","butterflies":"butterfly_anchors","fireflies":"firefly_anchors"}[kind]
		var values:Array=[]
		for i in range(int(config.limits[kind])):
			var at:Array=view.world.map_anchor(config[key][i%config[key].size()])
			values.append({"point":Vector2(at[0],at[1])+Vector2(rng.randf_range(-4,4),rng.randf_range(-3,3)),"phase":rng.randf()*TAU,"speed":rng.randf_range(.6,1.1)})
		if view.world.locations.v3() and not view.world.catalog.regions.home.layout.get("moon",{}).is_empty():
			for item in values.slice(0,mini(4,values.size())):
				var at:Array=view.world.map_anchor("moon.lookout");item.point=Vector2(at[0],at[1])+Vector2(rng.randf_range(-8,8),rng.randf_range(-8,8))
		particles[kind]=values
	wave_builds+=1;refresh_houses(view,true)
func refresh_houses(view:Node2D,force:bool=false)->void:
	if not force and view.clock<next_house_refresh:return
	next_house_refresh=view.clock+float(config.limits.house_refresh_seconds)
	houses.clear()
	for site in view.world.objects.values():
		if site.kind!="construction_site" or int(site.get("stage_index",0))<5 or not site.has("blueprint"):continue
		var profiles:Array=view.world.catalog.regions.home.layout.residential.filter(func(plot):return plot.site_id==site.id)
		var profile:String=profiles[0].retrofit_id if not profiles.is_empty() else ""
		var art:Dictionary=site.blueprint.artwork
		var key:String=site.id+":"+str(art.id)+":"+str(art.revision)
		var foot:Vector2=view.world.point(site)+Vector2(0,view.world.site_size(site).y/2)
		var chimneys:Array=config.chimneys.get(profile,config.chimneys_by_parent.get(art.get("provenance",{}).get("parent",art.id),[]))
		houses.append({"site_id":site.id,"foot":foot,"art":art,"key":key,"chimneys":chimneys})
		if window_cache.has(key):continue
		var source:Image=view.library.render(art,"stage_4");var count:=0;var mask:=Image.create(art.width,art.height,false,Image.FORMAT_RGBA8);mask.fill(Color.TRANSPARENT)
		for opening in art.get("openings",{}).get("windows",[]):
			for y in range(maxi(0,int(opening[1])),mini(art.height,int(opening[1]+opening[3]))):
				for x in range(maxi(0,int(opening[0])),mini(art.width,int(opening[0]+opening[2]))):
					var c:Color=source.get_pixel(x,y)
					var reference_x:int=int(art.width)-1-x if art.get("provenance",{}).get("mirror",false) else x
					var reference:Color=reference_glass.get_pixel(reference_x,y) if reference_x<reference_glass.get_width() and y<reference_glass.get_height() else Color.TRANSPARENT
					if c.a>.5 and c.b>c.r*1.08 and c.g>.15 and reference.a>.5 and reference.b>reference.r*1.08 and reference.g>.15:
						count+=1
						var warm:=Color(config.window_color);mask.set_pixel(x,y,Color(warm.r,warm.g*(.75+c.g*.25),warm.b,c.a))
		window_cache[key]=ImageTexture.create_from_image(mask);window_pixel_counts[site.id]=count
	var active:Array=houses.map(func(house):return house.key)
	for key in window_cache.keys():
		if key not in active:window_cache.erase(key)
func visible(view:Node2D,point:Vector2,margin:float=160)->bool:return view.get_viewport_rect().grow(margin).has_point(view.screen(point))
func draw_water(view:Node2D)->void:
	preload("res://scripts/moon_atmosphere.gd").draw(view)
	for wave in waves:
		if not visible(view,wave.point,40):continue
		var pulse:float=(sin(view.clock*TAU/float(config.wave_seconds)+wave.phase)+1)/2
		var p:Vector2=view.screen(wave.point+wave.normal*(.15+pulse*.4));var tangent:=Vector2(-wave.normal.y,wave.normal.x)
		view.draw_line((p-tangent*10*view.zoom).round(),(p+tangent*10*view.zoom).round(),Color(.88,.94,.88,(1-pulse)*.36),maxf(1,view.zoom))
func draw_foreground(view:Node2D)->void:
	refresh_houses(view)
	var state:=sample(view.world);var light:float=state.light;var t:float=view.clock
	if float(state.mist)>0:view.draw_rect(view.get_viewport_rect(),Color(.95,.92,.82,state.mist))
	var smoke_count:=0
	for house in houses:
		if not visible(view,house.foot):continue
		for chimney in house.chimneys:
			var anchor:Vector2=house.foot*32+Vector2(chimney[0]-house.art.anchor[0],chimney[1]-house.art.anchor[1])
			for i in range(int(config.limits.smoke_per_chimney)):
				if smoke_count>=int(config.limits.smoke_total):break
				smoke_count+=1
				var age:float=fposmod(t*.16+i/float(config.limits.smoke_per_chimney),1)
				var point:Vector2=anchor/32+Vector2(Motion.wind(t,house.foot)*age*.35+age*.4,-age*1.8)
				var p:Vector2=view.screen(point);var size:Vector2=Vector2(5+floor(age*5),4+floor(age*4))*view.zoom
				view.draw_rect(Rect2(p.round()-size/2,size),Color(.77,.77,.72,sin(age*PI)*.22))
	var weather:Dictionary=view.world.weather.current()
	var daylight:float=(1-light)*(0.2 if weather.id=="rain" else 1.0)
	for kind in ["birds","butterflies","fireflies"]:
		var alpha:float=light if kind=="fireflies" else daylight
		if alpha<.02:continue
		for particle in particles[kind]:
			var point:Vector2=particle.point+Vector2(sin(t*particle.speed*.17+particle.phase)*2,cos(t*.22+particle.phase)*.7)
			if not visible(view,point,20):continue
			var p:Vector2=view.screen(point);var flap:float=round(sin(t*(6 if kind=="birds" else 9)+particle.phase)*2)*view.zoom
			if kind=="birds":
				view.draw_line(p-Vector2(5,flap),p,Color(.27,.31,.29,alpha*.75),maxf(1,view.zoom));view.draw_line(p,p+Vector2(5,-flap),Color(.27,.31,.29,alpha*.75),maxf(1,view.zoom))
			elif kind=="butterflies":
				view.draw_rect(Rect2(p+Vector2(-3,flap),Vector2(3,2)*view.zoom),Color(.94,.73,.51,alpha*.85));view.draw_rect(Rect2(p+Vector2(1,-flap),Vector2(3,2)*view.zoom),Color(.9,.77,.61,alpha*.85))
			else:view.draw_rect(Rect2(p,Vector2(2,2)*view.zoom),Color(1,.92,.48,alpha*(.4+.5*absf(sin(t+particle.phase)))))
func draw_lights(view:Node2D,canvas:Node2D)->void:
	var state:=sample(view.world);var strength:float=state.light
	for string in config.strings:
		var at:Array=view.world.map_anchor(string.anchor);var center:Vector2=view.screen(Vector2(at[0],at[1]));var previous:=Vector2.ZERO
		for i in range(int(string.bulbs)):
			var fraction:float=float(i)/maxi(1,int(string.bulbs)-1)
			var point:Vector2=Vector2(string.start[0],string.start[1]).lerp(Vector2(string.end[0],string.end[1]),fraction)
			point.y+=sin(fraction*PI)*9;point.x+=round(Motion.wind(view.clock,Vector2(at[0],at[1]))*float(config.wind_pixels))
			var p:Vector2=(center+point*view.zoom).round()
			if i>0:canvas.draw_line(previous,p,Color(.35,.3,.23,.75)*state.tint,maxf(1,view.zoom))
			if strength>.01:canvas.draw_rect(Rect2(p-Vector2.ONE*2*view.zoom,Vector2.ONE*4*view.zoom),Color(1,.79,.4,strength))
			# Small original-palette cloth flags move by whole pixels with the shared breeze.
			if i%2==0:canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-3,3)*view.zoom,p+Vector2(3,3)*view.zoom,p+Vector2(1,10)*view.zoom]),Color(.66,.49,.34,.75)*state.tint)
			previous=p
	if strength<=.01:return
	for key in view.world.catalog.regions.home.layout.lamps:
		var at:Array=view.world.map_anchor(key);var pos:Vector2=view.screen(Vector2(at[0],at[1]))
		if not view.get_viewport_rect().grow(150).has_point(pos):continue
		var texture:Texture2D=view.props.textures.light
		canvas.draw_texture_rect(texture,Rect2(pos-view.props.anchors.light*view.zoom,texture.get_size()*view.zoom),false,Color(1,.84,.56,strength*.8*float(config.get("ground_light_gain",1.8))))
		canvas.draw_texture_rect(lamp_glass,Rect2(pos-view.props.anchors.lamp*view.zoom,lamp_glass.get_size()*view.zoom),false,Color(1,1,1,strength*.7))
	for house in houses:
		if not visible(view,house.foot):continue
		var mask:Texture2D=window_cache[house.key];var art:Dictionary=house.art
		canvas.draw_texture_rect(mask,Rect2(view.screen(house.foot)-Vector2(art.anchor[0],art.anchor[1])*view.zoom,mask.get_size()*view.zoom),false,Color(1,1,1,strength*float(config.get("window_strength",1.0))))
	# Reuse the existing fire-state truth; cold/empty stations never gain a fire glow.
	for barbecue in view.world.barbecues.values():
		if barbecue.fireside.active() and not barbecue.fireside.burning():continue
		var heat:float=1.0 if barbecue.fireside.burning() else Motion.heat(barbecue.station.state)
		if heat<=0:continue
		var p:Vector2=view.screen(view.world.point(barbecue.station))
		for radius in [130,100,70,40]:canvas.draw_circle(p-Vector2(0,6)*view.zoom,radius*view.zoom,Color(1,.62,.24,.065*strength*heat))
func stats()->Dictionary:
	return {"waves":waves.size(),"birds":particles.get("birds",[]).size(),"butterflies":particles.get("butterflies",[]).size(),"fireflies":particles.get("fireflies",[]).size(),"window_masks":window_cache.size(),"wave_cache_builds":wave_builds,"window_pixels":window_pixel_counts.duplicate(),"max_smoke":int(config.limits.smoke_total)}
