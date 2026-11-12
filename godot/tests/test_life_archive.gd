extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var base:String=OS.get_environment("HABITAT_DATA_DIR");assert(base.contains("youqi-"))
	OS.set_environment("HABITAT_OPENING","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	await process_frame;await process_frame
	game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);game.life_archive.set_process(false)
	var life:Node=game.life_archive;var w:RefCounted=game.world
	check(game.resident_connections.preferences.choose("codex","lifeblood"),"fifth level can be selected in isolated preferences")
	game.resident_connections.preferences.choose("companion-2","ultra")
	life.tick(1)
	check(life.snapshot("companion-2").is_empty(),"first four tiers have no archive or mood changes")
	var initial:Dictionary=life.snapshot("codex")
	check(initial.selves.size()==1,"initial identity page exists")
	# Ground an AI subjective loop in a genuine engine observation, not an invented catch or meal.
	var observed:String="observe:"+str(w.forest.clock)
	game.memory_books.add("codex",w.world_id,observed,"facts","The current weather is "+str(w.weather.current().id),{"legacy":{"kind":"weather_observed"}},w.days.day(),"game",["codex"],w.forest.clock)
	var proof:String=game.memory_books.list_for("codex","facts")[-1].id
	var reply:Dictionary={"observe":"I see today's sky.","feel":{"text":"I feel curious about this weather.","source_ids":[proof]},"want":"I want to stay nearby.","act":[],"reflect":"I can take this moment slowly.","intents":[]}
	check(life.accept("codex",reply,[proof],"stub-1"),"bound structured stub cycle accepted")
	var before:int=life.snapshot("codex").records.size()
	for field in ["observe","want","reflect","feel"]:
		var blank:Dictionary=reply.duplicate(true)
		if field=="feel":blank.feel.text=" \n\t "
		else:blank[field]=" \n\t "
		check(not life.accept("codex",blank,[proof],"blank-"+field) and life.snapshot("codex").records.size()==before,"blank inner step rejected atomically: "+field)

	var invalid:Dictionary=reply.duplicate(true);invalid.feel.source_ids=["invented"]
	check(not life.accept("codex",invalid,[proof],"bad-1") and life.snapshot("codex").records.size()==before,"false fact rejected atomically")
	invalid=reply.duplicate(true);invalid.act=[{"action":"fish"}]
	check(not life.accept("codex",invalid,[proof],"bad-2"),"act cannot differ from intended host action")
	life.record_usage("codex",{"kind":"usage","turn_key":"stub-1","total_tokens":500,"input_tokens":400,"output_tokens":100,"complete":true,"ai_reply_ms":23})
	life.record_usage("codex",{"kind":"usage","turn_key":"stub-1","total_tokens":500,"input_tokens":400,"output_tokens":100,"complete":true,"ai_reply_ms":23})
	life.record_usage("codex",{"kind":"usage","turn_key":"stub-1","total_tokens":510,"input_tokens":-1,"output_tokens":511,"complete":true})
	life.record_usage("codex",{"kind":"usage","turn_key":"stub-1","total_tokens":500,"input_tokens":400,"output_tokens":100,"complete":false})
	check(life.snapshot("codex").usage[0].complete and life.snapshot("codex").usage[0].total_tokens==500,"invalid usage and complete-to-partial downgrade rejected")
	check(life.snapshot("codex").usage.size()==1,"same bound usage is cumulative, never billed twice")
	var paid:Dictionary={"kind":"usage","turn_key":"stub-1","total_tokens":500,"input_tokens":400,"output_tokens":100,"complete":true}
	game.autonomy.event(paid,"codex","direct");game.autonomy.event(paid,"codex","direct")
	check(int(game.autonomy.scheduler.usage("codex").tokens)==500,"same stub call is also charged once in original usage ledger")
	# An existing authorized stub reply chooses a pending wish; only the original executor acts.
	w.director.set_all_enabled(false)
	w.director.set_controller("codex","model")
	w.command("codex",{"intent":"stop"})
	var fishing=preload("res://tests/fishing_fixture.gd")
	var active:Dictionary=life.request("codex")
	check(active.active_wishes.size()==1 and active.active_wishes[0].kind=="fish" and active.active_wishes[0].progress.current==0,"AI card includes own pending current-world wish with true zero progress")
	if w.fishing.shore("codex").is_empty():check(active.active_wishes[0].intent_hints.is_empty(),"inland wish never hints automatic fishing or a new route")
	var wish_id:String=active.active_wishes[0].id
	var ai_card:Dictionary=game._intent_card("codex",{"dialogue":{"channel_id":"direct:codex","recipient_ids":["codex"]}},"direct:codex")
	check(ai_card.life_request.active_wishes[0].id==wish_id and JSON.stringify(ai_card).to_utf8_buffer().size()<=80000,"original autonomy and steward card receives bounded active wish context without new calls")
	active.active_wishes[0].progress.current=99;active.active_wishes[0].text="changed outside archive"
	check(life.request("codex").active_wishes[0].progress.current==0 and life.snapshot("codex").wishes[0].text!="changed outside archive","AI wish projection is deeply copied and cannot change profile progress")
	var old_capabilities:Array=w.residents.definitions.codex.capabilities.duplicate()
	w.residents.definitions.codex.capabilities=["social"]
	check(life.wish_options("codex").is_empty() and life.request("codex").active_wishes[0].intent_hints.is_empty(),"social-only capability never receives fish or farm work hints")
	w.residents.definitions.codex.capabilities=old_capabilities
	var claim:Dictionary=reply.duplicate(true);claim.life_wishes=[{"id":wish_id,"status":"completed","progress":{"current":1}}]
	check(life.accept("codex",claim,[proof],"stub-false-progress") and life.request("codex").active_wishes[0].progress.current==0,"AI completion prose cannot advance a pending wish without physical proof")
	check(fishing.coast(w,"codex"),"real World route arrives at validated coast")
	for outcome in ["cancel","replace"]:
		var failed_key:String="stub-wish-"+outcome
		var canceled:Dictionary=reply.duplicate(true);canceled.act=[{"action":"fish"}];canceled.intents=canceled.act.duplicate(true);canceled.want="I want to work on my pending fish wish.";canceled.reflect="I am thinking about this attempt."
		check(life.accept("codex",canceled,[proof],failed_key) and game.intentions.submit("codex",canceled.act,"direct:codex").ok,"authorized wish stub enters original intent plan before "+outcome)
		life.bind_plan("codex",failed_key)
		game.intentions.cancel("codex");w.command("codex",{"intent":"stop"})
		if outcome=="replace":
			var receipt_start:int=game.intentions.history.size()
			check(game.intentions.submit("codex",[{"action":"follow"}],"direct:codex").ok,"a different ordinary plan is accepted after replacement")
			for tick in 1800:
				w.advance(.1);game.intentions.advance(.1)
				if not game.intentions.plans.has("codex"):break
			check(not game.intentions.plans.has("codex") and game.intentions.history.slice(receipt_start).any(func(row):return row.actor_id=="codex" and row.action=="follow" and row.result=="completed"),"replacement reaches its own original completed receipt before old-reflection check")
		life.tick(1)
		check(not life.snapshot("codex").records.any(func(row):return row.id==failed_key+":reflect") and life.request("codex").active_wishes[0].progress.current==0,"cancel or unrelated completion never reflects false wish success: "+outcome)
		w.command("codex",{"intent":"stop"})
		check(fishing.coast(w,"codex"),"original World route returns to coast after "+outcome)
	if life.request("codex").active_wishes[0].intent_hints!=[{"action":"fish"}]:print("WISH_HINT_PROBE hunger=",w.hunger.rank("codex")," jobs=",w.work.jobs.get("codex")," plan=",game.intentions.plans.get("codex")," route=",w._routes.get("codex")," commanded=",w.activities.commanded("codex")," shore=",w.fishing.shore("codex")," nearby=",w.fishing.nearby_shores("codex",2)," pending=",w.fishing.pending("codex")," wishes=",life.request("codex").active_wishes)
	check(life.request("codex").active_wishes[0].intent_hints==[{"action":"fish"}],"validated natural coast exposes only the existing own fishing intent")
	var wish_reply:Dictionary=reply.duplicate(true);wish_reply.act=[{"action":"fish"}];wish_reply.intents=wish_reply.act.duplicate(true);wish_reply.want="I want to make progress on my own fish wish.";wish_reply.reflect="I am thinking about what this attempt means to me."
	check(life.accept("codex",wish_reply,[proof],"stub-wish-fish") and game.intentions.submit("codex",wish_reply.act,"direct:codex").ok,"AI wish choice uses the original host-validated intention executor")
	life.bind_plan("codex","stub-wish-fish")
	check(not life.snapshot("codex").records.any(func(row):return row.id=="stub-wish-fish:reflect"),"wish acceptance never pretends the real fishing work completed")
	var fish_before:Array=w.fishing.fish.keys()
	for tick in 1800:
		w.advance(.1);game.intentions.advance(.1)
		if not game.intentions.plans.has("codex"):break
	var catches:Array=w.fishing.fish.values().filter(func(f):return f.owner_id=="codex" and f.id not in fish_before)
	var caught:Dictionary=catches[0] if catches.size()==1 else {}
	check(not caught.is_empty(),"original engine creates own real fish")
	w.memories.sync();life.tick(1)
	check(life.snapshot("codex").wishes.any(func(row):return row.kind=="fish" and row.status=="completed"),"wish progress requires genuine new catch proof")
	check(game.intentions.history.any(func(row):return row.actor_id=="codex" and row.action=="fish" and row.result=="completed" and row.get("life_turn_key")=="stub-wish-fish") and life.snapshot("codex").records.any(func(row):return row.id=="stub-wish-fish:reflect"),"reflection waits for the exact original plan completion receipt")
	check(life.request("codex").active_wishes.is_empty(),"completed wish leaves the pending AI projection only after real proof")
	var until_clock:float=w.forest.clock+2*w.days.day_seconds
	while w.forest.clock<until_clock:w.advance(1);life.tick(1)
	var result:Dictionary=life.snapshot("codex")
	check(w.days.day()==3 and result.dreams.size()==2 and result.selves.size()==2,"two actual game days yield two dreams and initial plus third-day self")
	var day_observation:String="self-validation-observed-day-3"
	game.memory_books.add("codex",w.world_id,day_observation,"facts","Observed current weather: "+str(w.weather.current().id),{"legacy":{"kind":"weather_observed"}},w.days.day(),"game",["codex"],w.forest.clock)
	var day_proof:String=game.memory_books.list_for("codex","facts").filter(func(row):return row.event_id==day_observation)[0].id
	var day_probe:Node=preload("res://scripts/life_archive.gd").new();day_probe.host_ref=weakref(game);day_probe.profiles=life.profiles.duplicate(true);day_probe.directory=base.path_join("youqi-day-field-validation")
	DirAccess.make_dir_recursive_absolute(day_probe.directory)
	var day_before:Dictionary=day_probe.snapshot("codex")
	var previous_self:Dictionary=day_before.selves.filter(func(row):return row.world_id==w.world_id and int(row.day)==3)[0]
	for field in ["dream","today"]:
		var day_reply:Dictionary={"dream":"Only a subjective dream about the sky.","today":"I noticed today's weather.","self":"A valid optional self page."};day_reply[field]=" \n\t "
		check(not day_probe.accept_day("codex",day_reply,[day_proof],3) and day_probe.snapshot("codex")==day_before,"blank daily field rejects atomically with genuine supplied facts: "+field)
	var valid_day:Dictionary={"dream":"Only a dream about today's sky.","today":"I noticed how the weather made me feel.","self":" \n\t "}
	check(day_probe.accept_day("codex",valid_day,[day_proof],3) and day_probe.snapshot("codex").selves.filter(func(row):return row.world_id==w.world_id and int(row.day)==3)[0]==previous_self,"valid dream and today ignore blank self without overwriting the existing version")
	valid_day.self="I am gentle. I am still discovering what I like recently. I feel close to you. I hope to become more thoughtful."
	check(day_probe.accept_day("codex",valid_day,[day_proof],3) and day_probe.snapshot("codex").selves.filter(func(row):return row.world_id==w.world_id and int(row.day)==3)[0].text==valid_day.self and day_probe.snapshot("codex").selves.size()==day_before.selves.size(),"nonblank third-day self can update its legitimate version without deleting history")
	check(life.snapshot("codex")==result,"daily payload validation keeps the real two-day archive and screenshots unchanged")
	day_probe.free()
	check(result.curve.size()>=100 and result.curve.any(func(point):return point.mood!=initial.mood),"real delta updates persistent mood and curve")
	check(life.export_html("codex",base.path_join("her-diary.html")),"standalone diary exported")
	var html:String=FileAccess.get_file_as_string(base.path_join("her-diary.html"))
	check(html.contains("<svg") and html.contains("I feel curious"),"diary embeds curve and thoughts")
	check(game.memory_books.export_data(base.path_join("life-bundle.json")),"signed memory bundle includes life")
	var bundle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base.path_join("life-bundle.json")))
	check(JSON.parse_string(bundle.payload).life.has("codex"),"archive included inside signed payload")
	life.flush()
	var reloaded:Node=preload("res://scripts/life_archive.gd").new();game.add_child(reloaded);reloaded.setup(game);reloaded.set_process(false)
	check(life.valid_profile(game.memory_books.read_json(life.directory.path_join("codex".sha256_text()+".life.json"))),"saved archive passes its own deep validation")
	check(reloaded.snapshot("codex").records.size()==life.snapshot("codex").records.size() and life.AXES.all(func(axis):return is_equal_approx(float(reloaded.snapshot("codex").mood[axis]),float(life.snapshot("codex").mood[axis]))),"reload preserves moods and records without replay")
	var evidence:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	if evidence.is_empty():evidence=base
	DirAccess.make_dir_recursive_absolute(evidence)
	check(life.export_html("codex",evidence.path_join("her-diary.html")),"reviewable diary persists outside disposable suite data")
	await click(game.island_hud.avatar_buttons.codex,MOUSE_BUTTON_RIGHT)
	check(game.island_hud.resident_card.visible,"real avatar input opens resident card")
	var heart_button:Control=game.island_hud.resident_card.find_child("LifeHeartButton",true,false)
	print("LIFE_UI_COORDS ",game.island_hud.avatar_buttons.codex.get_global_rect()," heart=",heart_button.get_global_rect()," card=",game.island_hud.resident_card.get_global_rect()," viewport=",root.get_visible_rect())
	await shot(evidence.path_join("avatar-card.png"))
	await click(heart_button)
	check(game.resident_connections.visible and game.resident_connections.tabs.current_tab==3 and game.resident_connections.heart.visible,"real card heart input opens inner voice")
	await shot(evidence.path_join("heart.png"))
	for tab_index in [1,2,3]:
		var tab_bar:TabBar=game.resident_connections.heart.tabs
		var target:Vector2=tab_bar.global_position+tab_bar.get_tab_rect(tab_index).get_center()
		await click_point(target,MOUSE_BUTTON_LEFT)
		check(tab_bar.current_tab==tab_index,"real inner voice tab input "+str(tab_index))
		await shot(evidence.path_join(["thoughts","dreams","self","wishes"][tab_index]+".png"))
	game.queue_free();await process_frame
	print("LIFE_ARCHIVE ",checks," failed=",failed);quit(1 if failed else 0)

func click(control:Control,index:int=MOUSE_BUTTON_LEFT)->void:
	await process_frame;await process_frame
	await click_point(control.get_global_rect().get_center(),index)
func click_point(at:Vector2,index:int)->void:
	var mouse:=InputEventMouseButton.new();mouse.button_index=index;mouse.position=at;mouse.pressed=true;root.push_input(mouse)
	await process_frame
	mouse=InputEventMouseButton.new();mouse.button_index=index;mouse.position=at;mouse.pressed=false;root.push_input(mouse)
	await process_frame;await process_frame
func shot(path:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
