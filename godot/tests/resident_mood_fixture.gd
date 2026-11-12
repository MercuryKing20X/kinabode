extends RefCounted
const Places=preload("res://scripts/map_locations.gd")
const F=preload("res://tests/cooking_fixture.gd")
const M=preload("res://tests/memory_fixture.gd")
static func shared_meal(world: RefCounted) -> bool:
	if not F.job(world,"human",{"intent":"chop","target_id":"home.tree.01"}) or not F.job(world,"human",{"intent":"forage","target_id":"home.mushrooms.1"}):return false
	return preload("res://tests/barbecue_fixture.gd").meal(world,"single:mushroom",["human","codex"])
class NoNeeds extends "res://scripts/resident_needs.gd":
	func choose(_world:RefCounted,_id:String)->Dictionary:return {}
class NoScenes extends "res://scripts/scene_speech.gd":
	func choose(_id:String)->Dictionary:return {}
static func idle(world: RefCounted) -> void:
	# C: derived mood idle speech must not start a competing default-follow route.
	world.activities.default_follow_excluded["codex"]=true
	world.personality.config.fact_events_enabled=false # Isolate derived-mood speech; real event reactions have their own probes.
	world.director.set_all_enabled(false);world.days.config.small_after=world.days.day_seconds+1;world.days.config.greeting_after=world.days.day_seconds+1
	world.scene_speech=NoScenes.new(world)
	world.director.routines.codex.needs=NoNeeds.new()
	var routine: RefCounted=world.director.routines.codex;routine.set_enabled(true);routine.chatter=true;routine.next_speech=0;routine.next_decision=INF;routine.last_walk=0
