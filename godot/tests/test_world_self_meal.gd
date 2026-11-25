extends SceneTree

class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return true
	func _send(_payload:Dictionary)->bool:return true

func _initialize()->void:run.call_deferred()

func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.begins_with("/tmp/") and not directory.begins_with("/var/folders/"):
		quit(1);return
	set_meta("title_opening","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game)
	game.set_process(false)
	game.save_enabled=false
	var world:RefCounted=game.world
	var fire:RefCounted=world.barbecues["home.barbecue"].fireside
	if fire.burning():
		quit(1);return
	world.storage.take({"wood":world.storage.count("wood")})
	world.storage.add({"wood":2})
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	for id in ids:
		world.hunger.ensure(id)
		world.hunger.states[id].elapsed=float(world.hunger.config.thresholds[3])+1
	var human:Vector2=world.point(world.actors.human)
	var total:=0
	var elapsed:=0.0
	for tick in range(4800):
		world.advance(.2)
		elapsed+=.2
		total=0
		for id in ids:
			if int(world.hunger.states[id].meals)>0:total+=1
		if total==4:break
		if tick%40==0:await process_frame
	var fell:bool=world.work.events.any(func(e):return e.get("intent")=="gather_wood" and e.get("status")=="completed")
	var still:bool=human==world.point(world.actors.human)
	print("WORLD_SELF_MEAL diners=",total," seconds=",elapsed," harvested=",fell," human_still=",still," wood=",world.storage.count("wood"))
	game.queue_free()
	await process_frame
	quit(0 if total==4 and fell and still else 1)
