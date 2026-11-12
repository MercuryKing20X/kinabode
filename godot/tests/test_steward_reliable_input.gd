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
	for attempt in range(3):
		pool.receive("codex",{"kind":"state","state":"disconnected"})
		if pool.retry_due.has("codex"):pool.retry_due.codex=0;pool._process(.1);await frames()
	check(pool.retries.codex==3 and not pool.retry_due.has("codex"),"retry cap three")
	var panel:Node=preload("res://scripts/connection_overview.gd").new();root.add_child(panel);panel.setup(dir);panel.open();await frames()
	var button:Button=UI.descendants(panel).filter(func(n):return n is Button and n.name=="persona_codex")[0]
	check(await UI.click(self,button),"real persona button click");await frames();await shot("persona-full")
	var dialog:Node=panel.get_node("PersonaEditor");var editor:TextEdit=UI.descendants(dialog).filter(func(n):return n is TextEdit)[0]
	check(editor.text==Cards.card("codex").text,"full world and resident persona displayed")
	editor.text+="\n测试修改";check(await UI.click(self,dialog.get_ok_button()),"save persona click");await frames()
	check(Cards.card("codex","",dir).text.ends_with("测试修改"),"isolated override saved")
	panel.show_persona("codex");await frames();dialog=panel.get_node("PersonaEditor");editor=UI.descendants(dialog).filter(func(n):return n is TextEdit)[0]
	check(await UI.click(self,UI.descendants(dialog).filter(func(n):return n is Button and n.name=="RestorePersona")[0]),"restore default click")
	check(editor.text==Cards.card("codex").text,"default restored in editor");await shot("persona-restored")
	check(await UI.click(self,dialog.get_ok_button()),"persist default click")
	print("RELIABLE_INPUT ",checks," failed=",failed);panel.queue_free();pool.queue_free();await frames();quit(1 if failed else 0)
