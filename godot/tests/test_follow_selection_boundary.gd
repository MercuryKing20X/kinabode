extends SceneTree
const W=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func goal(w:RefCounted,id:String)->Vector2:
	for offset in [Vector2(4,0),Vector2(-4,0),Vector2(0,4),Vector2(0,-4),Vector2(6,6),Vector2(-6,-6)]:
		var at:Vector2=w.point(w.actors[id])+offset
		if w.walkable(w.actors[id].region_id,at) and not w.find_route(id,at).is_empty():return at
	return Vector2.INF
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=W.new("res://content/home-v3/world.json")
	w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	assert(Opening.apply(w,w.library,"showcase").ok)
	w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true)
	w.director.set_controller("codex","model")
	for tick in 10:w.advance(.1)
	check(w.activities.following.has("codex") and w.activities.explicit_selected.is_empty(),"automatic default following creates no explicit-selection authority")
	var at:Vector2=goal(w,"codex")
	check(at.is_finite() and w.command("codex",{"intent":"move","x":at.x,"y":at.y}).ok,"model-controlled resident can use own ordinary move during automatic proximity")
	var own_route:Variant=w._routes.get("codex")
	w.advance(.1)
	check(not w._routes.has("codex") or is_same(w._routes.codex,own_route),"default following does not overwrite actual own move route")
	check(w.activities.set_followers(["codex","npc.mira"]).ok and w.activities.explicit_selected.keys().size()==2,"explicit host selection marks exactly selected participants")
	at=goal(w,"codex")
	var previous:Variant=w._routes.get("codex")
	var quiet:float=w.director.routines.codex.visual_quiet_until
	check(at.is_finite() and w.command("codex",{"intent":"move","x":at.x,"y":at.y}).get("error")=="following_active","ordinary model move cannot replace explicit selection")
	check(is_same(w._routes.get("codex"),previous) and w.director.routines.codex.visual_quiet_until==quiet,"rejected move leaves route and original quiet state untouched")
	check(w.model_social_command("npc.mira",{"intent":"unfollow"}).ok and w.activities.explicit_selected.has("codex") and not w.activities.explicit_selected.has("npc.mira"),"own unfollow changes only that resident's selection")
	check(w.model_social_command("npc.mira",{"intent":"follow"}).ok and w.activities.explicit_selected.has("codex") and w.activities.explicit_selected.has("npc.mira"),"own follow preserves the other resident's explicit selection")
	at=goal(w,"codex")
	check(at.is_finite() and w.host_command("codex",{"intent":"move","x":at.x,"y":at.y}).ok,"explicit host command pauses selection authority and starts original route")
	check(w.activities.following.has("codex") and w.activities.explicit_selected.has("codex") and not w.host_issuing.has("codex") and w.activities.explicit_selected.has("npc.mira"),"host pause retains source and return preference and changes no other selection")
	var arrived:=false
	for tick in 3000:
		w.advance(.02)
		if w.point(w.actors.codex).distance_to(at)<.2:arrived=true;break
	check(arrived and w.activities.explicit_selected.has("codex"),"real host movement completes while exact explicit selection protection remains")
	at=goal(w,"codex")
	check(at.is_finite() and w.command("codex",{"intent":"move","x":at.x,"y":at.y}).get("error")=="following_active","ordinary move remains rejected after completed host task")
	check(w.activities.explicit_selected.has("npc.mira"),"completed task does not alter another participant's selection")
	print("Follow selection boundary: ",checks," failed=",failed);quit(1 if failed else 0)
