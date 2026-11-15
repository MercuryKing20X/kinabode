extends "res://tests/test_simple_connection_input.gd"
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	root.size=Vector2i(1280,800)
	var fonts:=Theme.new();fonts.default_font=preload("res://assets/fonts/NotoSansSC.ttf");root.theme=fonts
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir)
	pool.factory=func(_id):return Stub.new()
	await frames()
	pool.connect_ai("codex");await frames();pool.set_management("codex",true)
	var original:Node=pool.links.codex
	pool.receive("codex",{"kind":"state","state":"disconnected"})
	check(pool.retries.codex==1,"first retry scheduled")
	pool.retry_due.codex=0;pool._process(.1);await frames()
	check(pool.links.codex==original and pool.states.codex.state=="ready" and pool.management("codex"),"same bound link and management recovered")
	# B: DIRECTION 2026-11-10 “任何原因断开…都自动重连”; ready closes a failure episode.
	check(not pool.retries.has("codex") and not pool.retry_due.has("codex"),"successful ready clears the completed failure episode")
	for attempt in range(3):
		pool.receive("codex",{"kind":"state","state":"disconnected"})
		check(pool.retries.get("codex",0)==1 and pool.retry_due.has("codex"),"new outage starts one bounded pending retry")
		pool.retry_due.codex=0;pool._process(.1);await frames()
		check(pool.links.codex==original and pool.states.codex.state=="ready" and not pool.retries.has("codex"),"each successful reconnect keeps exact link and clears its episode")
	var panel:Node=preload("res://scripts/connection_overview.gd").new();root.add_child(panel);panel.setup(dir);panel.open();await frames()
	var portrait:Control=UI.descendants(panel).filter(func(n):return n is Control and n.name=="persona_codex")[0]
	await UI.reveal(self,portrait)
	var point:Vector2=portrait.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=down;root.push_input(event,true);await process_frame
	check(panel.has_node("PersonaEditor"),"real persona portrait click");await frames();await shot("persona-full")
	var dialog:Node=panel.get_node("PersonaEditor");var editor:TextEdit=UI.descendants(dialog).filter(func(n):return n is TextEdit)[0]
	check(editor.text==Cards.card("codex").text,"full world and resident persona displayed")
	editor.text+="\n测试修改";check(await UI.click(self,dialog.get_ok_button()),"save persona click");await frames()
	check(Cards.card("codex","",dir).text.ends_with("测试修改"),"isolated override saved")
	panel.show_persona("codex");await frames();dialog=panel.get_node("PersonaEditor");editor=UI.descendants(dialog).filter(func(n):return n is TextEdit)[0]
	check(await UI.click(self,UI.descendants(dialog).filter(func(n):return n is Button and n.name=="RestorePersona")[0]),"restore default click")
	check(editor.text==Cards.card("codex").text,"default restored in editor");await shot("persona-restored")
	check(await UI.click(self,dialog.get_ok_button()),"persist default click")
	print("RELIABLE_INPUT ",checks," failed=",failed);panel.queue_free();pool.queue_free();await frames();quit(1 if failed else 0)
