extends "res://tests/test_brain_input.gd"
func run()->void:
	base_directory=OS.get_environment("HABITAT_DATA_DIR");evidence=OS.get_environment("HABITAT_BRAIN_EVIDENCE");media=OS.get_environment("HABITAT_BRAIN_MEDIA")
	DirAccess.make_dir_recursive_absolute(media);root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	node_added.connect(func(node):
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":node.set_process(false);node.dialogue_adapter_factory=func(_id,_scope):return Fake.new())
	await fresh_title(7)
	var w:RefCounted=game.world
	for tick in 200:game._process(.25)
	game.view.follow_player=false;game.view.center=w.point(w.actors.human)
	# Exactly sixty seconds of real simulated play and real viewport frames.
	for frame in 120:
		for tick in 2:game._process(.25)
		game.view._process(.5);await shot("interaction-minute-%03d"%frame)
	var delivered:Array=[]
	for b in w.director.brains.values():delivered.append_array(b.interactions.receipts)
	check(delivered.any(func(row):return row.event=="interaction" and row.scene in ["idle","rain"]),"standing without input delivers a real idle or current-weather interaction")
	var target:String="companion-2"
	game._select_chat(target)
	var refusals:=0;var accepts:=0
	for trial in 1:
		await text_input("小蓝陪我玩")
		if not w.director.brains[target].refusal.is_empty():
			refusals+=1
			check(not str(w.director.brains[target].refusal.reason).is_empty(),"actual social refusal carries reason")
		else:accepts+=1
		game.chat.hide();game.chat_input.release_focus()
		for tick in 160:game._process(.25)
		if refusals>0 and accepts>0:break
	var orders:Array=[]
	for who in w.director.brains:
		game._select_chat(who)
		await text_input("帮我砍树" if who=="codex" else "帮我砍1棵树")
		game.chat.hide();game.chat_input.release_focus()
		for tick in 10:game._process(.1)
		var result:Dictionary=game.local_host_commands.last_execution.duplicate(true)
		print("TYPED_LABOR ",who," result=",result," plans=",game.intentions.plans.get(who,{})," job=",w.work.jobs.get(who,{})," eligibility=",game.local_host_commands.eligible(who,"chop")," clock=",w.forest.clock," rank=",w.hunger.rank(who))
		check(result.get("ok",false) and who in result.get("actors",[]),"labor order accepted without personality refusal "+who)
		orders.append({"actor":who,"result":result,"job":w.work.jobs.get(who,{}).duplicate(true)})
		game.chat.hide();game.chat_input.release_focus()
	# Await actual original wood jobs, without hunger or yield parameter changes.
	for tick in 6000:
		game._process(.1);game.local_host_commands._process(.1)
		if orders.all(func(row):return not w.work.jobs.has(row.actor)):break
	print("LABOR_FINAL jobs=",w.work.jobs," receipts=",w.work.events)
	for row in orders:
		check(w.work.events.any(func(e):return e.get("actor_id","")==row.actor and e.get("job_id","")==row.job.get("id","") and e.get("status","")=="completed"),"labor exact physical completion "+row.actor)
	# Revisit the social request after the actual work, respecting original hunger.
	game._select_chat(target)
	for trial in 12:
		await text_input("小蓝陪我玩")
		if not w.director.brains[target].refusal.is_empty():
			refusals+=1
			check(not str(w.director.brains[target].refusal.reason).is_empty(),"social refusal has an explicit reason")
		else:accepts+=1
		game.chat.hide();game.chat_input.release_focus()
		for tick in 160:game._process(.25)
		if refusals>0 and accepts>0:break
	check(refusals>0 and accepts>0,"actual typed social invitations exercise acceptance and refusal")
	# Actual portrait click opens the original bilingual mind panel.
	game.chat.hide();game.island_hud.open_connections(target);await process_frame
	var portrait_point:Vector2=game.resident_connections.portrait.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=portrait_point;event.global_position=portrait_point;event.pressed=down;root.push_input(event,true);await process_frame
	var panels:Array=UI.descendants(root).filter(func(n):return n.get_script()!=null and n.get_script().resource_path=="res://scripts/brain_panel.gd" and n.visible)
	check(not panels.is_empty() and panels[-1].actor_id==target,"mind is bound to exact selected resident")
	if not panels.is_empty():
		var mind:Control=panels[-1]
		for locale in ["zh","en"]:
			game.LocalText.select(game.data_dir,locale);mind.refresh()
			check(mind.body.text.contains(w.director.brains[target].interactions.receipts.back()[locale]),"mind shows actual delivered interaction "+locale)
			await shot("interaction-mind-"+locale)
		mind.hide()
	game.resident_connections.close_panel()
	# Explicit host button starts stewardship, never a simulated assistant or model call.
	game.steward.open_setup("codex");await process_frame
	check(await UI.click(self,game.steward.setup_button),"real mouse confirms stewardship")
	check(game.steward.active,"real UI enables stewardship")
	for tick in 1600:game._process(.25)
	var dispatch:Array=[]
	for name in DirAccess.get_files_at(w.director.brain_trace_directory):
		for line in FileAccess.get_file_as_string(w.director.brain_trace_directory.path_join(name)).split("\n",false):
			var row:Dictionary=JSON.parse_string(line)
			if row.get("event")=="dispatch" and row.get("source")=="steward":dispatch.append(row)
	check(not dispatch.is_empty() and dispatch.all(func(row):return row.get("via")=="ResidentBrain"),"steward dispatches have brain execution receipts")
	var result_file:=FileAccess.open(evidence.path_join("interactions-input.json"),FileAccess.WRITE)
	result_file.store_string(JSON.stringify({"social_accepts":accepts,"social_refusals":refusals,"orders":orders,"dispatch":dispatch,"delivered":delivered},"\t"));result_file.close()
	for link in game.links.values():check(link is Fake and link.sent.is_empty(),"prebuilt stub zero real model calls")
	game.queue_free();await process_frame
	print("BRAIN_INTERACTIONS_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
