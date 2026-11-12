extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Motion=preload("res://scripts/meal_motion.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:RefCounted=F.fresh();w.director.set_all_enabled(false)
	assert(preload("res://tests/backpack_fixture.gd").wood(w,1) and F.mushroom(w))
	w.hunger.start()
	for tick in range(1250):w.advance(.5)
	assert(BBQ.light(w))
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	for i in range(ids.size()):
		var id:String=ids[i];var at:Vector2=Vector2(60+i*2,72)
		assert(F.job(w,id,{"intent":"move","x":at.x,"y":at.y}))
	for id in ids:w.director.routines[id].set_enabled(true)
	w.advance(10)
	assert(BBQ.approach(w))
	# A new explicit meal, real food/fuel, all four actually hungry and invited.
	assert(w.life.fireside.invite(ids).ok and w.life.fireside.roast_host("single:mushroom").ok)
	for id in ids:
		assert(w.hunger.rank(id)>=2)
		assert(w.hunger.rushing(id),"every invited hungry resident uses a real rush route: "+id)
		assert(w.movement_speed(id)*32==360)
		var style:Dictionary=Motion.style(w,id,w.hunger.rank(id))
		assert(not style.blow and style.chew_at<=.2 and style.cycles>=4)
	print("All four invited hungry residents have actual360px/s routes and prompt four-cycle eating")
	quit()
