extends RefCounted
## Authored small overlay using existing canvas, no asset/physics/RNG side effects.
static func draw(view: Node2D) -> void:
	if view.region_id!="home":return
	var weather: Dictionary=view.world.weather.current();var area: Rect2=view.get_viewport_rect()
	if float(weather.tint)>0:view.draw_rect(area,Color(.2,.3,.38,float(weather.tint)))
	if float(weather.fog)>0:
		if view.world.catalog.manifest.get("template_id","")=="home-v3":
			view.draw_rect(area,Color(.82,.88,.84,float(weather.fog)))
		else:
			for band in range(6):
				var y: float=fmod(band*area.size.y/5+sin(view.clock*.07+band)*18,area.size.y)
				view.draw_rect(Rect2(0,y,area.size.x,area.size.y/6),Color(.82,.88,.84,float(weather.fog)))
	for index in range(int(weather.rain)):
		var x: float=fposmod(index*97.3-view.clock*32,area.size.x)
		var y: float=fposmod(index*173.1+view.clock*230,area.size.y)
		view.draw_line(Vector2(floor(x),floor(y)),Vector2(floor(x)-3,floor(y)+11),Color(.75,.87,.88,.48),1)
