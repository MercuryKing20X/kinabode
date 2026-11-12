extends SceneTree
func _initialize()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(1);return
	var world:=preload("res://scripts/world_state.gd").new();world.residents.provision(world)
	world.actors.human.name="留住的名字";world.actors.human.name_version=1;world.actors.human.custom_appearance=true;world.actors.human.appearance_id="human-starter"
	world.actors.codex.name="原来的伙伴";world.actors.codex.controller="local"
	{"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items={"wood":7}
	assert(preload("res://scripts/save_store.gd").save_world(world,dir));quit()
