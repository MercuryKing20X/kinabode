extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
func _initialize()->void:call_deferred("run")
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world;var center:Vector2=w.point(w.life.station)
	var index:=0
	for id in w.actors:
		var goal:Vector2=center+Vector2(index*2-4,8)
		for n in range(20):
			if w.walkable("home",goal) and not w.find_route(id,goal).is_empty():break
			goal+=Vector2(0,1)
		assert(w.command(id,{"intent":"move","x":goal.x,"y":goal.y}).ok)
		index+=1
	for i in range(3000):
		game._process(.1);game.view._process(.1)
		if w._routes.is_empty():break
	var count:=0
	for id in w.actors:
		var before:Vector2=w.point(w.actors[id]);var found:=false
		for offset in [Vector2(50,0),Vector2(-50,0),Vector2(0,50),Vector2(0,-50)]:
			var goal:Vector2=before+offset
			if w.walkable("home",goal) and not w.find_route(id,goal).is_empty():
				assert(w.command(id,{"intent":"move","x":goal.x,"y":goal.y}).ok);found=true;break
		if found and w.is_running(id):count+=1
	assert(count==5,"all five are genuinely running at measurement start")
	game.view.center=w.point(w.actors.human);game.view.follow_player=true;game.view.zoom=1
	var started:int=Time.get_ticks_usec();var frames:=120
	for i in range(frames):
		game._process(1.0/60);game.view._process(1.0/60);game.view.queue_redraw();await process_frame
	var fps:float=frames*1000000.0/(Time.get_ticks_usec()-started)
	print("Actual viewport performance: ",fps," FPS / ",frames," frames; runners initially=",count,"; engine fixture, not player input; unavailable atlases use original fallback")
	game.queue_free();await process_frame;quit()
