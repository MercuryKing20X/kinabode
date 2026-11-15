extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Migration=preload("res://scripts/resort_revision_migration.gd")
const Save=preload("res://scripts/save_store.gd")
var failed:=false
func check(ok:bool,label:String)->bool:
	if not ok:failed=true;push_error(label)
	return ok
func _initialize()->void:
	# Frozen resort world predates session_generation. Reproduce its constructor,
	# registration and reset exactly; suite rejects every SCRIPT ERROR as well.
	var legacy:RefCounted=Migration.old_world()
	check(legacy.get("session_generation")==null,"frozen fixture really lacks session generation")
	for brain in legacy.director.brains.values():
		brain.reset()
		check(brain.generation==0,"missing old generation resets safely")
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not check(not directory.is_empty(),"isolated fixture directory required"):quit(1);return
	var library:=preload("res://scripts/character_library.gd").new()
	library.configure(directory.path_join("works"));legacy.library=library
	if not check(preload("res://scripts/world_opening.gd").apply(legacy,library,"standard").ok,"frozen standard opening applies"):quit(1);return
	legacy.director.set_all_enabled(false)
	# Reconstructed old-save fixture only, inside the runner's isolated directory.
	legacy.actors.codex.carry={"wood":3}
	if not check(Save.save_world(legacy,directory),"reconstructed old save writes"):quit(1);return
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("island-v2.json")))
	raw.vacation_version=1
	var file:=FileAccess.open(directory.path_join("island-v2.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(raw));file.close()
	var restored:=World.new("res://content/home-v3/world.json")
	restored.library=library;restored.residents.provision(restored)
	var result:Dictionary=Save.load_world(restored,directory)
	if not check(result.get("ok",false) and result.get("loaded",false),"real Save load migrates resort-v1"):quit(1);return
	check(restored.actors.codex.carry==raw.actors.codex.carry,"owned carry preserved")
	check(restored.storage.saved().items.size()==raw.storage.items.size(),"same exact storage item keys")
	for item in raw.storage.items:
		check(restored.storage.count(item)==int(raw.storage.items[item]),"same exact JSON-equivalent count: "+item)
	check(restored.memories.records==raw.shared_memories.records,"retained memory facts unchanged")
	for brain in restored.director.brains.values():
		brain.reset();check(brain.generation==restored.session_generation,"live generation takes over after migration")
	restored.intelligence.activate_presets();restored.director.set_all_enabled(true)
	var before:float=restored.director.time
	for i in range(120):restored.advance(.1)
	check(restored.director.time>before,"migrated live world advances normally")
	print("Brain legacy initialization: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
