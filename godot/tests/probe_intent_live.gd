extends SceneTree
var link:Node
var done:=false
var rows:Array=[]
var current:Dictionary={}
var started:=0
func _initialize()->void:call_deferred("run")
func event(value:Dictionary)->void:
	if value.kind=="usage":current.merge(value,true)
	if value.kind=="intent_result":current.reply=value.get("speech","");current.intents=value.get("intents",[])
	if value.kind=="error":current.error=value.get("message","");done=true
	if value.kind=="state" and value.get("turnComplete",false):done=true
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not dir.contains("habitat-live-test-"):quit(1);return
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	link=preload("res://scripts/companion_link.gd").new();link.helper_filename="intent_companion.py";link.world_id=w.world_id;root.add_child(link);link.event_received.connect(event)
	for words in ["你好，今天想聊什么？","海边真好看。","你喜欢什么？","帮我种萝卜","去收菜","帮我浇水","跟着我","叫小蓝一起来","你在做什么？","仓库有什么？"]:
		current={"text":words};done=false;started=Time.get_ticks_msec()
		var snap:Dictionary=w.observe("codex",{"limit":4})
		snap.intent_card={"self":{"id":"codex","activity":w.actors.codex.activity,"hunger":w.hunger.summary("codex").get("state","")},"nearby":[],"stock":w.storage._items,"places":["farm","coast","campfire"],"human_recent":[words],"memory":{"daily":[],"about_you":[],"facts":[]},"local_execution":{"measurement_only":true}}
		link.send_message(words,snap)
		while not done and Time.get_ticks_msec()-started<90000:await create_timer(.05).timeout
		current.elapsed_ms=Time.get_ticks_msec()-started;rows.append(current.duplicate(true))
		print("LIVE_INTENT_RESULT ",JSON.stringify(current))
		if not done or current.has("error"):break
	var file:=FileAccess.open(dir.path_join("measurements.json"),FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
	link.shutdown();await create_timer(.5).timeout;quit()
