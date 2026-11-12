extends "res://tests/test_resort_revision_migration.gd"
## Retain strict optional milestone parsing; retired paid projects refund exactly once.
func _initialize()->void:
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("optional-works"))
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,"standard").ok,"real current opening for optional progress")
	var s:RefCounted=w.their_island
	var valid:Dictionary={"unlocked":true,"introduced":true,"arrivals":["codex"]}
	check(s.valid_saved(valid),"valid retained optional milestone")
	for invalid in [{},{"unlocked":1,"introduced":false,"arrivals":[]},{"unlocked":false,"introduced":true,"arrivals":[]},{"unlocked":true,"introduced":true,"arrivals":["codex","codex"]},{"unlocked":true,"introduced":false,"arrivals":["unknown"]},{"unlocked":true,"introduced":false,"arrivals":[],"job":"invented"}]:
		check(not s.valid_saved(invalid),"reject malformed retained milestone "+str(invalid))
	s.restore(valid)
	check(s.saved()==valid and w.memories.records.is_empty(),"retained milestone is not invented history")
	check(s.pending.is_empty() and s.grants.is_empty() and w.work.jobs.is_empty(),"milestone restore grants no authority or jobs")
	var optional_dir:String=OS.get_environment("HABITAT_DATA_DIR").path_join("optional-progress")
	check(preload("res://scripts/save_store.gd").save_world(w,optional_dir),"save retained optional progress without fabricated memories")
	var loaded:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");loaded.residents.provision(loaded);loaded.library=w.library
	check(preload("res://scripts/save_store.gd").load_world(loaded,optional_dir).ok and loaded.their_island.saved()==valid,"actual reload preserves optional milestones exactly")
	check(loaded.memories.records.is_empty() and loaded.work.jobs.is_empty() and loaded.their_island.pending.is_empty() and loaded.their_island.grants.is_empty(),"reload adds no evicted history or construction authority")
	super._initialize()
