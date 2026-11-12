extends SceneTree
## Southern outdoor construction is retired; validated legacy refunds remain covered
## by test_resort_revision_migration and test_their_island_progress.
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Outdoor=preload("res://scripts/outdoor_building.gd")
var failed:=false
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var stock:Dictionary=w.storage.saved();var objects:Array=w.objects.keys();var sites:Array=w.leisure.sites.keys();var memories:Dictionary=w.memories.saved()
	for point in [Vector2(81,185),Vector2(93,208),Vector2(57,235)]:
		check(w.resort.contains(point),"current holiday ground")
		var result:Dictionary=Outdoor.new_plot(w,point)
		check(not result.ok and result.get("error")=="vacation_only","no new southern construction foundation")
		for template in ["outdoor-chair","outdoor-path","outdoor-flowers"]:
			check(w.library.artworks.has(template),"original template retained for legacy validation")
			result=w.leisure.place(template,point)
			check(not result.ok and result.get("error")=="vacation_only","no new southern outdoor construction "+template)
		check(w.storage.saved()==stock and w.objects.keys()==objects and w.leisure.sites.keys()==sites and w.memories.saved()==memories,"rejected placement preserves all real material and facts")
	check(w.work.jobs.is_empty() and Outdoor.saved(w).is_empty(),"no jobs or dynamic foundations created")
	print("Holiday outdoor construction rejection failed=",failed);quit(1 if failed else 0)
