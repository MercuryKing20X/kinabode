extends SceneTree
var failed:=false
func check(v:bool,label:String)->void:
	if not v:failed=true;push_error(label)
func _initialize()->void:
	var w:RefCounted=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	var f:RefCounted=w.flower_creation;f.next_auto=INF
	w.storage.add({"rose_red":200})
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	var result:Dictionary=f.arrange_group(ids,{"intent":"arrange_flowers","text":"HI","color":"red"})
	check(result.ok and f.jobs.size()==4,"explicit host design dispatches four original routes")
	var identity:String=f.jobs.codex.pattern_id
	var total:int=0
	for job in f.jobs.values():total+=job.points.size();check(job.pattern_id==identity,"all participants share one design identity")
	check(total==f.pixels({"text":"HI"}).size(),"disjoint reservations equal one HI")
	for i in range(4000):
		w.advance(.1)
		if f.jobs.is_empty():break
	check(f.jobs.is_empty() and f.flowers.size()==total,"group completes one actual HI")
	check(w.storage.count("rose_red")==200-total,"no duplicated group payment or flowers")
	check(f.flowers.values().all(func(flower):return flower.pattern_id==identity),"saved placement retains shared identity")
	check(f.flowers.values().map(func(flower):return flower.actor_id).any(func(id):return id!="codex"),"real multiple contributors retained")
	print("flower group failed=",failed);quit(1 if failed else 0)
