extends SceneTree
class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func probe_connection()->bool:return false
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("DAILY ",label," ",ok)
	if not ok:failures+=1
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if not dir.contains("youqi-test-"):quit(2);return
	OS.set_environment("HABITAT_OPENING","standard")
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir)
	pool.factory=func(_id):return Fake.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame;await process_frame
	game.memory_life.set_process(false);game.life_archive.set_process(false)
	var w:RefCounted=game.world
	var b:RefCounted=w.director.brains.codex
	var daily:RefCounted=game.life_archive.daily
	daily.attach("codex",b)
	w.director.set_all_enabled(true)
	w.advance(.25)
	var card:Dictionary=b.intention.card()
	check(card.wish.get("choose",{}).has("sea"),"only the actual available coast is offered for today's wish")
	daily.select("codex",["sea","plaza"])
	check(daily.rows("codex").size()==2 and not daily.rows("codex")[0].attempted,"choice alone neither starts nor completes")
	var human:Array=w.actors.human.position.duplicate()
	var stock:Dictionary=w.storage.saved()
	var plan:Dictionary={"activity":"watch_sea","place":"sea","reason":"看一会儿浪。","with":"human","bring":"invented_shell"}
	check(b.intention.accept(plan),"a valid seaside visit survives two bad optional fields")
	for tick in 460:
		w.advance(.25)
		if daily.rows("codex").any(func(row):return row.goal=="sea" and row.status=="completed"):break
	check(daily.rows("codex").any(func(row):return row.goal=="sea" and row.attempted and row.status=="completed"),"World arrival and observing time complete the exact daily wish")
	check(game.memory_books.list_for("codex","facts").any(func(row):return row.params.get("legacy",{}).get("kind")=="daily_wish_completed" and row.params.legacy.first),"first real completion is kept in the memory book")
	check(w.actors.human.position==human and w.storage.saved()==stock and not w._routes.has("human"),"no human movement or material credit")
	check(b.intention.card().feedback.any(func(row):return row.reason=="unavailable_item" and not row.message.is_empty()),"the next card explains why the shell was dropped")
	daily.evening("codex")
	check(daily.rows("codex").any(func(row):return row.goal=="plaza" and row.status=="expired"),"unattempted wish expires without completion")
	game.queue_free();await process_frame
	quit(1 if failures else 0)
