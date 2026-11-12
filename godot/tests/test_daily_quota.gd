extends "res://tests/test_simple_connection_input.gd"
func run()->void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	OS.set_environment("HABITAT_OPENING","standard")
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir);pool.factory=func(_id):return Stub.new()
	await frames()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game)
	await frames(2);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	game._simple_connection_action("codex","connect");game._simple_connection_action("companion-2","connect");await frames(2)
	check(game.world.actors.codex.controller=="model" and pool.valid("codex") and pool.links.codex is Stub and pool.links.codex.starts==1 and pool.links.codex.chats==0,"Snow starts connected through the exact offline stub before exhaustion")
	game.connection_overview.open();await frames(2)
	var quota_box:SpinBox=game.connection_overview.find_child("daily_quota_codex",true,false)
	check(quota_box!=null,"today allowance is directly visible without advanced settings")
	if quota_box==null:game.queue_free();quit(1);return
	var edit:LineEdit=quota_box.get_line_edit();edit.grab_focus()
	var select:=InputEventKey.new();select.keycode=KEY_A;select.ctrl_pressed=true;select.meta_pressed=true;select.pressed=true;root.push_input(select)
	for value in [53,48]:
		var key:=InputEventKey.new();key.unicode=value;key.keycode=KEY_5 if value==53 else KEY_0;key.pressed=true;root.push_input(key)
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true;root.push_input(enter);await frames(2)
	check(pool.daily_limit("codex")==50,"real keyboard input sets only Snow's daily allowance")
	var caption:Label=game.connection_overview.find_child("daily_quota_label_codex",true,false)
	var progress:ProgressBar=game.connection_overview.find_child("quota_progress_codex",true,false)
	check(caption!=null and caption.text==preload("res://scripts/localization.gd").text("quota.limit") and progress!=null and progress.max_value==50 and progress.show_percentage,"committed allowance immediately updates its visible caption and progress without waiting for usage")
	await create_timer(.35).timeout;await frames(2)
	await quota_shot("quota-before",game)
	game.connection_overview.hide()
	game.autonomy.event({"kind":"usage","turn_key":"stub-paid-1","total_tokens":60,"input_tokens":50,"output_tokens":10,"complete":true},"codex","direct")
	game.autonomy.event({"kind":"usage","turn_key":"stub-paid-1","total_tokens":60,"input_tokens":50,"output_tokens":10,"complete":true},"codex","direct")
	check(int(pool.quota_usage("codex").tokens)==60,"cumulative usage is charged once")
	var notices:Array=[];pool.quota_local_requested.connect(func(id,first):notices.append({"id":id,"first":first}))
	pool._process(.3);await frames(2)
	check(game.world.actors.codex.controller=="local" and not pool.valid("codex"),"only exhausted actor returns to local")
	check(game.world.actors["companion-2"].controller=="model" and pool.valid("companion-2"),"other actor connection continues")
	game.connection_overview.open();await frames(2);await quota_shot("quota-after",game);game.connection_overview.hide()
	check(notices.size()==1 and notices[0].first,"exhaustion notice emitted once")
	check(pool.connect_ai("codex",game.world.world_id)==null,"same-day reconnect cannot bypass exhausted quota")
	var native:Node=preload("res://scripts/companion_link.gd").new();native.resident_id="codex";native.world_id=game.world.world_id
	check(native._daily_quota_reached(),"native chat and autonomy share pre-start checker without a real process")
	native.free()
	var ledger:Dictionary=game.autonomy.scheduler.usage("companion-2");ledger.tokens=10;ledger.reserved=40;ledger.unknown_turns=1
	game.autonomy.scheduler.preferences.save_accounting("companion-2",ledger);pool.set_daily_limit("companion-2",50)
	check(pool.quota_reached("companion-2"),"unknown reserved usage is conservatively included")
	var other:=preload("res://scripts/resident_intelligence_preferences.gd").new();other.setup(dir,"second-world")
	var second:Dictionary=ledger.duplicate(true);second.tokens=5;second.reserved=10;second.unknown_turns=0
	other.save_accounting("companion-2",second)
	check(int(pool.quota_usage("companion-2").tokens)==15 and int(pool.quota_usage("companion-2").reserved)==50,"same resident's natural-day usage sums across worlds without rewriting old ledgers")
	var receipt:Dictionary={"kind":"usage","turn_key":"global-stub-1","model":"fake","total_tokens":20,"input_tokens":15,"output_tokens":5,"complete":true}
	var before:int=pool.api_tokens();pool.receive("codex",receipt);pool.receive("codex",receipt)
	check(pool.api_tokens()==before+20,"duplicate complete global usage does not double count")
	receipt=receipt.duplicate();receipt.scope="group";pool.receive("codex",receipt)
	check(pool.api_tokens()==before+40,"group scope has its own genuine bound usage")
	game.queue_free();await frames(1)
	print("DAILY_QUOTA ",checks," failed=",failed);quit(1 if failed else 0)

func quota_shot(name:String,_game:Node)->void:
	if DisplayServer.get_name()=="headless":return
	var out:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	if out.is_empty():out="/tmp/youqi-overnight-quota-evidence"
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
