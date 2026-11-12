extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	var w:=preload("res://scripts/world_state.gd").new()
	assert(preload("res://tests/memory_fixture.gd").populate(w,dir))
	w.memories.sync();var expected:=0
	for e in w.memories.records:expected+=e.participants.filter(func(id):return id!="human").size()
	for id in w.journal.discoveries:
		if id!="human":expected+=w.journal.discoveries[id].size()
	var books:=preload("res://scripts/memory_books.gd").new();assert(books.setup(dir))
	var began:int=Time.get_ticks_usec();var counts:Dictionary=books.migrate(w);var migration_ms:float=(Time.get_ticks_usec()-began)/1000.0
	assert(books.entries.size()==expected);assert(books.migrate(w).is_empty())
	var reload:=preload("res://scripts/memory_books.gd").new();began=Time.get_ticks_usec();assert(reload.setup(dir));var load_ms:float=(Time.get_ticks_usec()-began)/1000.0
	assert(reload.entries.size()==expected)
	print("MIGRATION ",JSON.stringify({"by_kind":counts,"expected":expected,"actual":books.entries.size(),"migration_ms":migration_ms,"load_ms":load_ms}))
	quit()
