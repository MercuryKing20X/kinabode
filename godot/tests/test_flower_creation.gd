extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(v:bool,label:String)->void:
	checks+=1
	if not v:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:RefCounted=World.new("res://content/home-v3/world.json")
	w.residents.provision(w)
	var f:RefCounted=w.flower_creation
	f.next_auto=INF
	# Stock is explicit isolated fixture inventory, never player data.
	w.storage.add({"wood":30,"rose_red":200,"rose_white":100})
	var id:String="codex"
	var start:Dictionary=w.host_command(id,{"intent":"arrange_flowers","text":"HI","color":"red"})
	check(start.ok,"HI accepted on genuinely open nearby land")
	if not start.ok:return
	var count:int=f.pixels({"text":"HI"}).size()
	for tick in range(4000):
		w.advance(.1)
		if not f.active(id):break
	check(f.flowers.size()==count,"HI walks every cell and places every rose")
	check(w.storage.count("rose_red")==200-count,"actual warehouse debits")
	check(w.point(w.actors[id]).distance_to(w.point(w.actors.human))<4,"returns to human after arranging")
	var copy:Dictionary=f.saved();check(f.valid_saved(copy,w.actors),"strict save validator accepts generated state")
	var old:int=w.storage.count("rose_red")
	var one:Dictionary=f.flowers.values()[0]
	var picked:Dictionary=w.host_command(id,{"intent":"pick_flower","position":one.position,"region_id":one.region_id})
	check(picked.ok,"pick existing flower accepted")
	for tick in range(4000):
		w.advance(.1)
		if not f.active(id):break
	check(w.storage.count("rose_red")==old+1 and f.flowers.size()==count-1,"pick returns exactly one real rose")
	check(not f.execute(id,{"intent":"arrange_flowers","text":"INVALID"}).ok,"six character limit")
	check(not f.execute(id,{"intent":"place_flower","position":[NAN,0]}).ok,"nonfinite position rejected")
	var before:int=w.storage.count("rose_red")
	var gift:Dictionary=w.host_command(id,{"intent":"gift_flower","color":"red"})
	check(gift.ok and w.storage.count("rose_red")==before-1,"gift reserves one rose before walk")
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	check(Save.save_world(w,dir),"save during physical flower offering")
	var reloaded:RefCounted=World.new("res://content/home-v3/world.json")
	reloaded.residents.provision(reloaded)
	check(Save.load_world(reloaded,dir).ok,"load flower snapshot")
	check(reloaded.storage.count("rose_red")==before and reloaded.flower_creation.jobs.is_empty(),"reload refunds in-flight offering once and stops task")
	for tick in range(1000):
		w.advance(.1)
		if not f.active(id):break
	check(f.first_received and w.storage.count("rose_red")==before,"actual gift received without creation or loss")
	check(not w.host_command(id,{"intent":"gift_flower"}).ok,"daily gift limit")
	check(not f.execute(id,{"intent":"trade_flowers","quantity":2}).ok,"resident trade requires actual manager authority")
	for ch in f.glyphs.font:check(f.pixels({"text":ch}).size()>0,"authored 5x7 glyph "+ch)
	for pattern in f.glyphs.patterns:check(f.pixels({"pattern":pattern}).size()>0,"pattern "+pattern)
	print("flower creation: %s checks, failed=%s"%[checks,failed])
	quit(1 if failed else 0)
