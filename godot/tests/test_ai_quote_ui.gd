extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
class Stub extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func send_message(_text:String,_world:Dictionary)->void:pass
var failed:=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("AI_QUOTE_UI ",label," ",ok)
	if not ok:failed=true
func run()->void:
	root.size=Vector2i(1280,800)
	var base:=OS.get_environment("HABITAT_DATA_DIR")
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,base)
	pool.factory=func(_id):return Stub.new()
	var books:=preload("res://scripts/memory_books.gd").new();books.setup(base)
	books.offer_ai_quote("codex","test-world","bound-test-turn","你说喜欢雨，我也记着今天的海风。","stub API",1,"direct:codex")
	books.add("codex","test-world","real-test-quote","facts","我喜欢雨",{},1,"local",["human"])
	var panel:=preload("res://scripts/memory_book_panel.gd").new();root.add_child(panel);panel.setup(books);panel.open()
	await process_frame;await process_frame
	var buttons:Array=UI.descendants(panel).filter(func(n):return n is Button and n.text=="记下来")
	check(buttons.size()==1,"one explicit player choice")
	if buttons.size()==1:check(await UI.click(self,buttons[0]),"real mouse selects quote")
	check(books.local_quotes("codex").size()==1 and books.latest_ai.is_empty(),"only selected quote persisted")
	panel.tabs.select(3);panel.refresh();await process_frame
	check(UI.descendants(panel).any(func(n):return n is Label and "AI 时期 · stub API" in n.text),"album displays provenance")
	panel.queue_free();pool.queue_free();await process_frame;quit(1 if failed else 0)
