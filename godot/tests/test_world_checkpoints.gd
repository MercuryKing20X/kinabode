extends SceneTree

const Checkpoints=preload("res://scripts/world_checkpoints.gd")
const Save=preload("res://scripts/save_store.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")
class Stub extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_args:Dictionary)->bool:return false
var failures:=0
var checks:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func run()->void:
	var path:=OS.get_environment("HABITAT_DATA_DIR")
	if not path.begins_with("/tmp/") and not path.begins_with("/var/folders/"):quit(2);return
	set_meta("title_opening","showcase")
	Pool.obtain(self,path).factory=func(_id):return Stub.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game)
	game.set_process(false)
	game.save_enabled=false
	var w:RefCounted=game.world
	check(w.opening_id=="showcase","showcase applied")
	var legacy:Dictionary={"actor_id":"codex","chapter_id":"codex.stars","source_ids":["actual legacy source".sha256_text()]}
	check(w.memories.record_event("story_chapter",legacy.chapter_id,["human","codex"],legacy),"legacy chapter still has a valid owner")
	legacy.chapter_id="npc.nora.beacon"
	check(not w.memories.record_event("story_chapter",legacy.chapter_id,["human","codex"],legacy),"legacy chapter cannot change owners")
	var points:=Checkpoints.new(w,path)
	points.tick(func():return "")
	check(points.entries().size()==1,"first-day snapshot")
	var initial:int=w.storage.count("wood")
	check(w.storage.take({"wood":2}).ok,"real warehouse debit")
	w.flower_creation.creations.projects["codex"]="Keep the project note"
	var error:=points.restore("1",path.path_join("island-v2.json"))
	check(error.is_empty(),"restore day one: "+error)
	check(w.storage.count("wood")==initial,"warehouse restored")
	check(w.flower_creation.creations.projects.get("codex")=="Keep the project note","resident project record retained")
	error=points.restore("undo",path.path_join("island-v2.json"))
	check(error.is_empty() and w.storage.count("wood")==initial-2,"undo returns pre-restore inventory: "+error)
	check(w.take_storage_host("wood",1).ok,"real warehouse transfer to backpack")
	var started:Dictionary=w.gathering.start("codex",{"intent":"gather_wood","tree_count":2})
	check(started.ok and points.working(),"real gathering in progress")
	error=points.restore("1",path.path_join("island-v2.json"))
	check(error=="busy" and w.work.jobs.has("codex"),"confirmation required without interrupting work")
	error=points.restore("1",path.path_join("island-v2.json"),true)
	check(error.is_empty() and not w.work.jobs.has("codex"),"confirmed restore stops gathering: "+error)
	check(w.storage.count("wood")==initial and w.actors.human.carry.is_empty(),"day snapshot does not duplicate withdrawn wood")
	error=points.restore("undo",path.path_join("island-v2.json"))
	check(error.is_empty() and w.storage.count("wood")==initial-3 and w.actors.human.carry.get("wood")==1,"undo restores exact physical inventory: "+error)
	for i in 8:
		w.forest.advance(w.days.day_seconds)
		points.tick(func():return "")
	var rows:=points.entries()
	check(rows.size()==7 and int(rows[0].day)-int(rows[-1].day)==6,"last seven days retained")
	check(Save.save_world(w,path),"save world")
	check(Save.load_world(w,path).get("loaded",false),"reload world")
	check(Checkpoints.new(w,path).entries().size()==7,"snapshots reopened after load")
	print("WORLD_CHECKPOINTS checks=",checks," failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
