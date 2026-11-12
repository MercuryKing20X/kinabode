class_name VillageLife
extends RefCounted
# Legacy village catalog/provisioning. All runtime decisions live in ResidentDirector.
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var definitions: Array = []
var states: Dictionary = {}
var enabled := false:
	set(value):
		enabled=value
		if world.director!=null:
			for id in ids():
				if world.director.routines.has(id):world.director.routines[id].set_enabled(value)
var time := 0.0
var rng := RandomNumberGenerator.new()
func _init(source: RefCounted) -> void:
	_owner = weakref(source); rng.randomize()
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/villagers.json")).residents
func ids() -> Array:
	return definitions.map(func(definition): return definition.id)
func provision() -> void:
	for definition in definitions:
		if not world.actors.has(definition.id):
			world._add_actor(definition.id,definition.name,"npc",Vector2(definition.start[0],definition.start[1]))
		states[definition.id] = {"mode":"pause","next":time+1+states.size()*1.7,"index":0,"owned_route":false}
		if enabled:world.director.routines[definition.id].set_enabled(true)
