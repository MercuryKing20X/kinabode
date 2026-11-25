extends SceneTree

const Pool=preload("res://scripts/connection_session_pool.gd")
class Stub extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_args:Dictionary)->bool:return false

func _initialize()->void:run.call_deferred()

func run()->void:
	var path:=OS.get_environment("HABITAT_DATA_DIR")
	if not path.begins_with("/tmp/") and not path.begins_with("/var/folders/"):quit(2);return
	set_meta("title_opening","showcase")
	Pool.obtain(self,path).factory=func(_id):return Stub.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game)
	game.set_process(false)
	game.save_enabled=false
	var w:RefCounted=game.world
	var layer:RefCounted=w.flower_creation.creations
	var original:=["path","bench","lamp","sign","fence","fence_vertical","rock","sapling","table","barrel"]
	var origin:Vector2=w.point(w.actors.human).round()
	var test_tile:=Vector2.INF
	for radius in range(1,14):
		for offset in [Vector2(radius,0),Vector2(0,radius),Vector2(-radius,0),Vector2(0,-radius)]:
			var p:Vector2=origin+offset
			if layer.check("human","place_piece",{"item":"fence","position":[p.x,p.y]},true).is_empty() and w._apply_route("human",layer.approach("human",p)):
				test_tile=p
				break
		if test_tile.is_finite():break
	if not test_tile.is_finite():push_error("No reachable test cell");quit(1);return
	for _i in 600:
		if not w._routes.has("human"):break
		w.advance(.1)
	var checks:=0
	var failures:=0
	for id in layer.Catalog:
		if id in original:continue
		var step:Dictionary={"item":id,"position":[test_tile.x,test_tile.y]}
		var cost:int=layer.Catalog[id].material.wood
		if not w.storage.has({"wood":cost}):
			var job:Dictionary=w.gathering.start("human",{"intent":"gather_wood","tree_count":3})
			if not job.ok:push_error("Could not gather stock");quit(1);return
			for _i in 1800:
				if not w.work.jobs.has("human"):break
				w.advance(.1)
			if not w._apply_route("human",layer.approach("human",test_tile)):quit(1);return
			for _i in 600:
				if not w._routes.has("human"):break
				w.advance(.1)
		var before:int=w.storage.count("wood")
		var result:String=layer.commit("human","place_piece",step,"")
		checks+=1
		if result!="" or w.storage.count("wood")!=before-cost or layer.blocked("home",test_tile)==layer.Catalog[id].walkable:
			failures+=1
			push_error("Placement "+id+": "+result)
			continue
		result=layer.commit("human","remove_piece",step,"")
		checks+=1
		if result!="" or w.storage.count("wood")!=before-cost+floori(cost/2.0) or layer.blocked("home",test_tile):
			failures+=1
			push_error("Removal "+id+": "+result)
	print("WORLD_CATALOG checks=",checks," failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
