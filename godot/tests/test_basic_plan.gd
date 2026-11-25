extends SceneTree

const Save=preload("res://scripts/save_store.gd")
class Offline extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_data:Dictionary)->bool:return false
	func probe_connection()->bool:return false
var failed:=false

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	print("BASIC ",label," ",ok)
	failed=failed or not ok

func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(2);return
	OS.set_environment("HABITAT_OPENING","standard")
	set_meta("title_fresh",true);set_meta("title_opening","standard")
	preload("res://scripts/connection_session_pool.gd").obtain(self,dir).factory=func(_id):return Offline.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Offline.new()
	root.add_child(game);current_scene=game
	game.save_enabled=false;game.set_process(false)
	var w:RefCounted=game.world
	var notes:RefCounted=w.island_notes
	var b:RefCounted=w.director.brains.codex
	b.clock=w.director.time
	w.director.set_all_enabled(true)
	var door:Vector2=notes.places().get("doorstep",Vector2.INF)
	check(door.is_finite(),"valid existing house doorstep")
	if not door.is_finite():quit(1);return
	w.actors.codex.position=[door.x,door.y]
	w.actors.human.position=[door.x,door.y]
	w.storage.add({"rose_red":1,"mushroom":1})
	var before:int=w.storage.count("rose_red")
	var food:int=w.storage.count("mushroom")
	check(b.intention.basic.accept({"reason":"Leave a rose and a note","steps":[{"action":"pick_up","item":"rose_red"},{"action":"put_down","item":"rose_red"},{"action":"write_note","target":"human","place":"doorstep","text":"留给你的。","en":"I left this for you."}]},"local"),"shared executor accepts a three step plan")
	for tick in 10:w.advance(.25)
	if notes.gifts.is_empty():
		for file in DirAccess.get_files_at(b.trace_directory):
			for line in FileAccess.get_file_as_string(b.trace_directory.path_join(file)).split("\n",false):
				var event:Variant=JSON.parse_string(line)
				if event is Dictionary and event.get("actor")=="codex":print("BASIC TRACE ",line)
	check(w.storage.count("rose_red")==before-1 and notes.gifts.size()==1 and int(w.actors.codex.carry.get("rose_red",0))==0,"exactly one rose moved from the warehouse to the doorstep")
	check(notes.rows.size()==1,"note committed")
	if notes.gifts.is_empty() or notes.rows.is_empty():quit(1);return
	var gift:String=notes.gifts.keys()[0]
	var note:String=notes.rows.keys()[0]
	check(Save.save_world(w,dir) and Save.load_world(w,dir).get("loaded",false),"note and gift persist through disk")
	check(notes.read_note(note,"npc.nora").is_empty() and notes.read_note(note,"human").get("text")=="留给你的。","only the addressed player can read the note")
	check(notes.collect(gift) and not notes.collect(gift) and w.storage.count("rose_red")==before,"one explicit pickup restores one rose exactly once")
	b.finish("interrupted","fixture")
	check(b.intention.basic.accept({"reason":"Forbidden pickup","steps":[{"action":"pick_up","item":"mushroom"},{"action":"put_down","item":"rose_red"}]},"local"),"well-formed plan reaches step authorization")
	for tick in 4:w.advance(.25)
	check(w.storage.count("mushroom")==food and notes.gifts.is_empty() and b.intention.feedback_rows.any(func(row):return row.reason=="pickup_not_allowed"),"first failed step stops all later steps and preserves food")
	check(w.memories.records.any(func(row):return row.kind=="doorstep_note_first") and w.memories.records.any(func(row):return row.kind=="doorstep_gift_first"),"first receipt facts are recorded")
	quit(1 if failed else 0)
