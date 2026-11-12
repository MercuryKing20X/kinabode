extends "res://tests/test_intelligence_core_input.gd"
var seen:Dictionary={}
var lines:Dictionary={}
var counts:Dictionary={}
var contexts:Dictionary={}
var repeat_count:=0
var max_bubbles:=0
var samples:Array=[]
func collect()->void:
	for e in game.world.director.events:
		if seen.has(e.serial):continue
		seen[e.serial]=true
		var key:String=str(e.actor_id)+":"+str(e.text)
		if lines.has(key):repeat_count+=1
		lines[key]=true;counts[e.actor_id]=int(counts.get(e.actor_id,0))+1
		contexts[e.context]=int(contexts.get(e.context,0))+1
		samples.append(e.duplicate(true))
	max_bubbles=maxi(max_bubbles,game.view.speech_layout().size())
func step(seconds:float)->void:
	for i in int(seconds*10):
		game._process(.1);game.journey._process(.1);collect()
		if i%100==0:await process_frame
func run()->void:
	await fresh()
	await step(600)
	var idle_counts:Dictionary=counts.duplicate();var idle_contexts:Dictionary=contexts.duplicate()
	await picture("idle-600")
	# Actual viewport clicks request World routes; do not inject positions or resources.
	for lap in range(12):
		var p:Vector2=game.world.point(game.world.actors.human)
		var target:Vector2=p+Vector2(9 if lap%2==0 else -9,2 if lap%3==0 else -1)
		game.view.center=p;game.view.follow_player=false;await process_frame
		var at:Vector2=game.view.screen(target)
		for down in [true,false]:
			var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.double_click=true;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
		await step(15)
	await picture("moving-180")
	check(repeat_count==0,"no delivered line repeats during observation")
	check(counts.size()==4,"all four speak")
	var stats:Dictionary={"idle_seconds":600,"moving_seconds":180,"idle_counts":idle_counts,"idle_contexts":idle_contexts,"total_counts":counts,"contexts":contexts,"repeated":repeat_count,"max_bubbles":max_bubbles,"samples":samples,"scene_deliveries":game.world.scene_speech.delivered}
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("observation.json"),FileAccess.WRITE);f.store_string(JSON.stringify(stats,"  "));f.close()
	game.queue_free();await process_frame
	print("SCENE_OBSERVATION ",checks," failed=",failed);quit(1 if failed else 0)
