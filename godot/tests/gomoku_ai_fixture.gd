extends RefCounted
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
static func built() -> RefCounted:
	var w:=F.fresh();w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));w.library.resident_world=w
	if not F.job(w,"codex",{"intent":"gather_wood","tree_count":10}) or not F.job(w,"codex",{"intent":"build_facility","target_id":"play.gomoku"}):push_error("Real table construction failed")
	return w
static func advance(w: RefCounted,seconds: float) -> void:
	for i in range(int(ceil(seconds/.2))):w.advance(.2)
