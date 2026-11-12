extends SceneTree
class MouseObserver:
	extends Node
	var events:Array=[]
	func _input(event:InputEvent)->void:
		if event is InputEventMouseButton and event.pressed:
			events.append({"at":Time.get_ticks_msec(),"position":[event.position.x,event.position.y],"button":event.button_index})
var game:Node
var observer:MouseObserver
var output:String
var ready_to_observe:=false
var state_after:=0
var running_before:=false
var capture_until:=0
var capture_start:=0
var capture_index:=0
var capture_folder:String
var shot_after:=0
var busy:=false
var captures:Array=[]
var run_seen:Dictionary={}
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	root.size=Vector2i(1440,900);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	await process_frame;await process_frame
	game.save_enabled=false
	observer=MouseObserver.new();root.add_child(observer)
	root.title="有栖 RUN-V4 临时鼠标验收";root.grab_focus()
	ready_to_observe=true
func ui_nodes(node:Node,result:Array)->void:
	if node is Button and node.is_visible_in_tree():
		var rect:Rect2=node.get_global_rect();var viewport:Viewport=node.get_viewport()
		if viewport is Window and viewport.is_embedded():rect.position+=Vector2(viewport.position)
		result.append({"text":node.text,"name":str(node.name),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"disabled":node.disabled})
	for child in node.get_children():ui_nodes(child,result)
func snapshot()->void:
	var w:RefCounted=game.world;var actors:Dictionary={};var ui:Array=[]
	for id in w.actors:
		actors[id]={"position":w.actors[id].position.duplicate(),"appearance":w.actors[id].appearance_id,"activity":w.actors[id].activity,"facing":w.actors[id].facing,"running":w.is_running(id),"hunger":w.hunger.rank(id),"carry":w.actors[id].carry.duplicate(),"screen":[game.view.screen(w.point(w.actors[id])).x,game.view.screen(w.point(w.actors[id])).y]}
	ui_nodes(game,ui)
	var file:=FileAccess.open(output.path_join("current-state.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"clock":w.forest.clock,"actors":actors,"camera":[game.view.center.x,game.view.center.y],"zoom":game.view.zoom,"viewport":[root.size.x,root.size.y],"ui":ui,"mouse":observer.events,"captures":captures,"run_seen":run_seen},"  "));file.close()
func _process(_delta:float)->bool:
	if not ready_to_observe:return false
	var now:int=Time.get_ticks_msec()
	if now>=state_after:snapshot();state_after=now+250
	for id in game.world.actors:
		if game.world.is_running(id) and game.world.motion_state(id).moving:
			run_seen[id]={"at":now,"appearance":game.world.actors[id].appearance_id,"position":game.world.actors[id].position.duplicate(),"rushing":game.world.hunger.rushing(id)}
	var running:bool=game.world.is_running("human") and game.world.motion_state("human").moving
	if running and not running_before and now>=capture_until:
		capture_start=now;capture_until=now+3000;capture_index+=1
		capture_folder=output.path_join("native-"+str(capture_index).pad_zeros(2));DirAccess.make_dir_recursive_absolute(capture_folder)
		captures.append({"folder":capture_folder.get_file(),"started":now,"input":"native mouse only; observer has no route/action authority"})
	if now<capture_until and now>=shot_after and not busy:
		busy=true;shot_after=now+50;call_deferred("shot")
	running_before=running
	return false
func shot()->void:
	await RenderingServer.frame_post_draw
	var now:int=Time.get_ticks_msec();var path:String=capture_folder.path_join(str(now-capture_start).pad_zeros(4)+".png")
	root.get_texture().get_image().save_png(path)
	busy=false
