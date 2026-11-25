extends "res://tests/test_intent_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	w.director.set_all_enabled(false)
	w.director.set_controller("codex","model")
	for id in w.actors:
		if id!="human":w.activities.release_follow(id)
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	game._ensure_link("codex")
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	var tree:String=""
	for object in w.objects.values():
		if object.kind=="tree":tree=object.id;break
	check(not tree.is_empty(),"real tree exists")
	check(w.command("companion-2",{"intent":"chop","target_id":tree}).ok,"unrelated partner starts actual chop")
	var job:String=str(w.work.jobs.get("companion-2",{}).get("id",""))
	await text_input("去种菜")
	check(w.farms.orders.has("codex"),"named direct planting starts real farm order")
	check(w.work.jobs.get("companion-2",{}).get("id","")==job,"named planting preserves unrelated chop job")
	var link:Node=game.links.codex
	var key:String=link.turn_key
	game.connection_ui_states["codex:direct"]="ready"
	var words:Array=["你好呀","今天真舒服","你在想什么","我看着呢","去种菜","慢慢来","让他们去种菜","种地去","大家去种菜","谢谢小白"]
	for phrase in words:
		await text_input(phrase)
		check(link.turn_key==key and link.is_busy(),"typing preserves original in-flight turn "+phrase)
		check(game.chat_input.text.is_empty(),"native Enter submits "+phrase)
	check(link.sent.size()==1,"ten rapid inputs never start parallel inference")
	check(game.next_chat.get("codex",[]).size()==10,"all ten phrases retained in order")
	check(link.sent.all(func(entry):return entry.kind!="cancel" and entry.kind!="shutdown"),"no cancel or disconnect during typing")
	check(not w.work.events.any(func(entry):return entry.get("job_id","")==job and entry.get("status","") in ["cancelled","stopped"]),"unrelated real work receives no cancellation")
	link._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":key})
	await text_input("刚刚又想到")
	words.append("刚刚又想到")
	check(link.sent.size()==1 and game.next_chat.codex.size()==11,"fresh ready-period arrival appends behind older messages")
	# A completed reply must not let queue draining erase a new in-progress draft.
	var point:Vector2=game.chat_input.get_global_rect().get_center()
	for down in [true,false]:
		var click:=InputEventMouseButton.new();click.position=point;click.global_position=point;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down;root.push_input(click,true);await process_frame
	for down in [true,false]:
		var event:=InputEventKey.new();event.unicode="还".unicode_at(0);event.pressed=down;root.push_input(event,true);await process_frame
	while Time.get_ticks_msec()<int(game.next_chat_due.get("codex",0)):await create_timer(.05).timeout
	game._process(0)
	check(game.chat_input.text=="还" and link.sent.size()==1,"ready queue preserves native in-progress draft")
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_BACKSPACE;event.pressed=down;root.push_input(event,true);await process_frame
	game._process(0)
	check(link.sent.size()==2,"one coalesced next model round")
	check(link.sent[-1].text=="\n".join(words),"next round contains exact ordered input batch")
	check(game.next_chat.is_empty(),"batch drained once")
	game._process(0)
	check(link.sent.size()==2,"no repeated batch dispatch")
	var human_rows:Array=game.dialogue.histories[game.Channels.direct("codex")].filter(func(row):return row.sender_id=="human")
	check(human_rows.size()==12,"coalesced delivery never duplicates original human history")
	link._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":link.turn_key})
	game._ensure_group_link("codex")
	var group:Node=game.group_links.codex
	group.send_message("group in flight",{})
	var sent_before:int=link.sent.size()
	game._send_direct("codex","留到群聊之后")
	while Time.get_ticks_msec()<int(game.next_chat_due.get("codex",0)):await create_timer(.05).timeout;game._process(0)
	check(link.sent.size()==sent_before and game.next_chat.codex==["留到群聊之后"],"busy group retains direct batch without concurrent inference")
	group._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":group.turn_key})
	game._process(0)
	check(link.sent.size()==sent_before+1 and link.sent[-1].text=="留到群聊之后" and game.next_chat.is_empty(),"group completion releases retained direct batch exactly once")
	link._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":link.turn_key})
	var payloads:Array=["甲".repeat(3000),"乙".repeat(2000),"尾声"]
	game._send_direct("codex","开始长队列")
	var offset:int=link.sent.size()
	for payload in payloads:game._send_direct("codex",payload)
	link._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":link.turn_key})
	while Time.get_ticks_msec()<int(game.next_chat_due.get("codex",0)):await create_timer(.05).timeout
	for tick in range(4):
		game._process(0)
		if link.is_busy():link._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":link.turn_key})
	var delivered:Array=link.sent.slice(offset).filter(func(row):return row.kind=="chat")
	check(delivered.size()==2 and delivered.all(func(row):return row.text.length()<=4000),"over4000 queued characters use bounded model batches")
	check("\n".join(delivered.map(func(row):return row.text))=="\n".join(payloads),"bounded batches preserve every queued character in order")
	check(game.next_chat.is_empty() and game.next_chat_sources.is_empty(),"all batches and source references drain once")
	print("FLEXIBLE_QUEUE_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)
