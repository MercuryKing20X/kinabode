extends RefCounted
## Deterministic cosmetic moon phase; no gameplay RNG or clock ownership.
static func reflection_strength(world:RefCounted)->float:
	if world.moon==null or world.moon.config.is_empty() or world.days.phase().id!="night" or world.weather.current().id in ["rain","fog"]:return 0.0
	return (1-cos(world.moon.phase()*TAU/8))*.5
static func draw(view:Node2D)->void:
	var strength:=reflection_strength(view.world)
	if strength<=.001:return
	var at:Array=view.world.map_anchor("moon.reflection");var center:=Vector2(at[0],at[1])
	if not view.get_viewport_rect().grow(200).has_point(view.screen(center)):return
	for i in range(44):
		var y:float=(i-10)*.16;var spread:float=(.35+absf(y)*.15)*(1+sin(i*2.39+view.clock*.45)*.25)
		var p:Vector2=view.screen(center+Vector2(sin(i*1.31+view.clock*.24)*spread*.65,y))
		var width:float=(30+spread*30)*(0.65+sin(i*3.41)*.2)*view.zoom
		view.draw_line((p-Vector2(width,0)).round(),(p+Vector2(width,0)).round(),Color(.94,.91,.72,strength*(.44 if i<16 else .22)),maxf(1,view.zoom))
	# Moon disc on the water is broken into bands, never a solid overlay on land.
	for i in range(-8,9):
		var p:Vector2=view.screen(center+Vector2(0,i*.055))
		var radius:float=sqrt(maxf(0,64-i*i))*2.7*view.zoom
		view.draw_line((p-Vector2(radius,0)).round(),(p+Vector2(radius,0)).round(),Color(.98,.95,.79,strength*.48),maxf(1,view.zoom))
