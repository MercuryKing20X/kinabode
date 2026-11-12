extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var failed:=false
func check(value:bool,label:String)->void:
	if not value:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	for id in ["companion-2","npc.mira"]:
		var w:=F.fresh()
		check(F.mushroom(w) and BBQ.light(w),"real resources and host route")
		var fire:RefCounted=w.life.fireside
		# Transfer genuine warehouse stock into own carry, as a pending handover fixture.
		check(F.withdraw(w,id,"wood",1),"finite warehouse withdrawal")
		check(w.deliveries.request(id),"handover owns original World route")
		var carried:Dictionary=w.actors[id].carry.duplicate(true)
		check(fire.invite([id]).ok and fire.roast_host("single:mushroom").ok,"host confirms named guest")
		for tick in range(1500):
			w.advance(.1)
			if id in fire.state.current.eaters:break
		check(id in fire.state.current.eaters,"handover yields and guest actually eats: "+id)
		check(w.actors[id].carry==carried,"invitation never consumes or deposits guest goods")
		fire.end_circle("test end")
		w.actors[id].region_id="dark"
		check(not fire.can_invite([id]).ok and fire.can_invite([id]).get("error")=="different_region","different island explicitly rejected")
	print("barbecue invitation owned-route regression ",not failed)
	quit(1 if failed else 0)
