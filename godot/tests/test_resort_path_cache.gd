extends SceneTree
func _initialize()->void:
	var w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	var layout:Dictionary=w.catalog.regions.home.layout
	var count:=0
	var before:int=Time.get_ticks_usec()
	for y in range(0,450,2):
		for x in range(-190,170,2):
			var p:=Vector2(x+.5,y+.5)
			assert(w._layout_blocked_fast(layout,p)==preload("res://scripts/home_layout.gd").blocked(layout,p),"exact original static collision equivalence")
			count+=1
	w.home_island._prepare_road_topology()
	var edges:Array=w.home_island.road_edges.duplicate(true)
	w.home_island._prepare_road_topology()
	assert(w.home_island.road_edges==edges)
	var start:=Vector2(81,199);var finish:=Vector2(141,247)
	var path:Array[Vector2]=w.home_island.road_route(start,finish)
	for p in path:
		assert(w.segment_clear("home",start,p));start=p
	var t:int=Time.get_ticks_usec()
	w.find_route("human",Vector2(80,310))
	print("EXACT_COLD_ROUTE_MS ",(Time.get_ticks_usec()-t)/1000.0)
	assert(w._grids.has("home"))
	var grid:AStarGrid2D=w._grids.home
	var free_set:Dictionary={}
	for c in w._terrain_solids.home.free:free_set[c]=true
	for y in range(grid.region.position.y,grid.region.end.y):
		for x in range(grid.region.position.x,grid.region.end.x):
			var c:=Vector2i(x,y)
			assert(free_set.has(c)==w._terrain_walkable("home",Vector2(c)+Vector2(.5,.5)),"every terrain cell exact equivalence including water and bounds")
	for v in w.resort.config.villas:
		for y in range(int(v.position[1])-17,int(v.position[1])+19):
			for x in range(int(v.position[0])-19,int(v.position[0])+19):
				var cell:=Vector2i(x,y)
				assert(grid.is_point_solid(cell)==not w.walkable("home",Vector2(cell)+Vector2(.5,.5)),"exact villa collision raster equivalence")
	print("GRID_EQUIVALENCE passed elapsed_ms=",(Time.get_ticks_usec()-t)/1000.0)
	print("PATH_CACHE_EQUIVALENCE ",count," cells passed elapsed_ms=",(Time.get_ticks_usec()-before)/1000.0)
	quit()
