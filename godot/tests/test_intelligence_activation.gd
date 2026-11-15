extends SceneTree
const World=preload("res://scripts/world_state.gd")
class Hungry extends "res://scripts/hunger_system.gd":
	func rank(_id:String)->int:return 2
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=World.new();w.residents.provision(w);w.director.set_all_enabled(false);w.intelligence.activate_presets();w.hunger=Hungry.new(w)
	check(w.personality.tag("companion-2")=="lively" and w.personality.tag("npc.mira")=="laborious","new host presets have requested main traits")
	w.advance(.1)
	check(w.intelligence.active["companion-2"]==["glutton","clingy"],"food and clingy priority, maximum two")
	var original:Dictionary=w.intelligence.catalog.traits.glutton.weights.duplicate();w.intelligence.catalog.traits.clingy.weights={"nearby":99}
	check(w.intelligence.profile("companion-2").weights.nearby==original.nearby,"higher priority owns declared aspect")
	w.intelligence.catalog.traits.clingy.weights={}
	var initial:Array=w.intelligence.active["companion-2"].duplicate()
	for i in range(1000):w.advance(.01)
	check(w.intelligence.active["companion-2"]==initial,"1000 unchanged real ticks do not oscillate")
	w.actors.human.activity="watching";w.advance(.1)
	check("clingy" not in w.intelligence.active["companion-2"],"unmet condition exits")
	w.actors.human.activity="idle"
	for i in range(590):w.advance(.1)
	check("clingy" not in w.intelligence.active["companion-2"],"exit cooldown holds for 60 seconds")
	for i in range(20):w.advance(.1)
	check("clingy" in w.intelligence.active["companion-2"],"context can return after cooldown")
	w.intelligence.active["companion-2"]=[]
	check(w.intelligence.profile("companion-2").name==w.intelligence.catalog.traits.lively.name,"empty contexts return to main profile")
	check(is_equal_approx(w.intelligence.hunger_multiplier("companion-2"),float(w.intelligence.catalog.traits.lively.hunger_multiplier)),"no context uses main hunger multiplier")
	w.intelligence.active["companion-2"]=["glutton"]
	check(is_equal_approx(w.intelligence.hunger_multiplier("companion-2"),maxf(w.intelligence.catalog.traits.lively.hunger_multiplier,w.intelligence.catalog.traits.glutton.hunger_multiplier)),"context hunger takes bounded maximum")
	check(w.actors.human.position==w.catalog.manifest.spawn.position,"no human movement")
	var routine:RefCounted=w.director.routines.codex
	routine.preferences.weights={"watch":.5}
	w.advance(.1)
	check(routine.preferences.weights=={"watch":.5},"ordinary ticks preserve the decision selector's effective preferences")
	w.intelligence.assign("codex","resident-blue");w.advance(.1)
	check(routine.intelligence_preset_id=="resident-blue" and routine.preferences.fishing_style=="lively","an actual preset change refreshes effective preferences")
	print("Intelligence activation: ",checks," checks, failed=",failed);quit(1 if failed else 0)
