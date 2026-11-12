extends "res://tests/test_resort_holiday_input.gd"
## Integration/UI: BLOCKING actual World arrival/occupancy; ADVISORY art screenshots.
## One formal-world native input demonstration; no position/resource/hunger injection.
var frames:Array=[]
var gate_result:Dictionary={}
func walk(at:Vector2,measure:bool=false)->void:
	var ui:Node=game.get_node("ResortUI")
	if is_instance_valid(ui.menu) and ui.menu.visible:await UI.click(self,ui.menu.get_ok_button())
	await click_point(at)
	var elapsed:=0.0;var length:=0.0
	var previous:Vector2=game.world.point(game.world.actors.human)
	for i in 2200:
		var started:int=Time.get_ticks_usec()
		game._process(.1);elapsed+=.1
		var now:Vector2=game.world.point(game.world.actors.human);length+=now.distance_to(previous);previous=now
		if measure:
			game.view.center=now;game.view.queue_redraw();RenderingServer.force_draw(false)
			await process_frame
			frames.append((Time.get_ticks_usec()-started)/1000.0)
		elif i%50==0:await process_frame
		if i>(60 if measure else 2) and not game.world._routes.has("human"):break
	if measure:gate_result={"target":[at.x,at.y],"distance_tiles":length,"simulated_seconds":elapsed,"arrived":previous.distance_to(at)<.5}
	check(previous.distance_to(at)<.6,"native walk arrives "+str(at))
func run()->void:
	await fresh()
	for b in UI.descendants(game):
		if b is Button and b.text=="−":await UI.click(self,b);break
	var w:RefCounted=game.world
	await text_input("大家跟我来");game.chat.hide()
	await walk(Vector2(81,178))
	check(w.home_island.here(),"native original long bridge arrives on compact island")
	await walk(Vector2(81,190))
	check(w.objects.keys().filter(func(id):return str(id).begins_with("homelands.house.") or str(id).begins_with("homelands.free.")).is_empty(),"no old southern houses or foundations")
	check(w.resort.config.villas.size()==5,"five current villas")
	await capture_scene("compact-panorama-day",Vector2(81,207),.23)
	# Original invitation API is reached only by actual click + actual visible buttons.
	var pool:Dictionary=w.resort.activities["resort.human.pool"]
	await choose_activity("resort.human.pool",false)
	for i in 500:
		game._process(.1)
		if i%50==0:await process_frame
		if w.actors.keys().all(func(id):return w.resort.using(id)=="pool"):break
	check(pool.slots.size()>=6,"expanded pool has at least six exclusive slots")
	check(w.actors.keys().all(func(id):return w.resort.using(id)=="pool"),"all five arrive and use expanded pool")
	var points:Array=w.actors.values().map(func(a):return w.point(a))
	for i in points.size():
		for j in range(i+1,points.size()):check(points[i].distance_to(points[j])>=2,"pool bodies do not overlap")
	await capture_scene("expanded-pool-five",Vector2(pool.position[0],pool.position[1]),.8)
	# Explicit elsewhere click ends this host activity, then original follow command.
	await walk(Vector2(81,190))
	await text_input("大家跟我来");game.chat.hide()
	for v in w.resort.config.villas:
		var door:=Vector2(v.door[0],v.door[1])
		await walk(door+Vector2(4,3))
		var art:Texture2D=preload("res://scripts/resort_renderer.gd").texture(v.style,false)
		check(art!=null and art.get_size()==Vector2(640,512),"native 20x16 tile art640x512 "+v.key)
		await capture_scene("native-villa-"+v.key,Vector2(v.position[0],v.position[1]+2),1)
	await walk(Vector2(81,190))
	var farthest:Dictionary={};var distance:=-1.0
	for v in w.resort.config.villas:
		var d:float=Vector2(v.gate[0],v.gate[1]).distance_to(Vector2(81,190))
		if d>distance:distance=d;farthest=v
	var gate:Vector2=Vector2(farthest.gate[0],farthest.gate[1])
	var plaza_start:Vector2=Vector2(81,185)+(gate-Vector2(81,185)).normalized()*4
	await walk(plaza_start)
	await walk(gate,true)
	gate_result.origin=[plaza_start.x,plaza_start.y]
	check(gate_result.arrived and gate_result.distance_tiles<=12.5,"plaza to farthest courtyard gate within about twelve tiles")
	var total:=0.0
	for ms in frames:total+=ms
	var metrics:Dictionary={"frames":frames.size(),"average_frame_ms":total/maxi(1,frames.size()),"worst_frame_ms":frames.max() if not frames.is_empty() else 0,"gate":gate_result}
	# Natural DayCycle projection from actual elapsed simulation, no clock assignment.
	for i in 15000:
		if w.days.phase().id=="night":break
		game._process(.1)
		if i%300==0:await process_frame
	check(w.days.phase().id=="night","actual elapsed advance reaches night")
	await capture_scene("compact-panorama-night",Vector2(81,207),.23)
	FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	print("REVISION_METRICS ",JSON.stringify(metrics))
	print("RESORT_REVISION_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
