extends SceneTree
const Appearance=preload("res://scripts/house_appearance.gd")
const Library=preload("res://scripts/character_library.gd")
var failed:=false
func _initialize()->void:call_deferred("run")
func run()->void:
	var library=Library.new()
	var hashes:Array=[]
	for owner in Appearance.OWNERS:
		var site:Dictionary={"owner_id":owner}
		var day:Texture2D=Appearance.texture(site,library)
		var night:Texture2D=Appearance.texture(site,library,true)
		if day==null or night==null or day.get_image().get_data()==night.get_image().get_data():failed=true;push_error("day/night texture missing")
		hashes.append(day.get_image().get_data().hex_encode().sha256_text())
		if not Appearance.enabled(site):failed=true
		site.house_appearance="classic"
		if Appearance.enabled(site):failed=true
	for i in hashes.size():
		if hashes.count(hashes[i])!=1:failed=true;push_error("owner appearance duplicated")
	print("House appearance: five independent derivatives, day/night and classic toggle ",not failed)
	verify_reload(library)
	quit(1 if failed else 0)

func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func verify_reload(library:RefCounted)->void:
	const World=preload("res://scripts/world_state.gd")
	const Save=preload("res://scripts/save_store.gd")
	const Opening=preload("res://scripts/world_opening.gd")
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	check(directory.contains("youqi-"),"isolated test directory")
	for opening in ["standard","showcase"]:
		var w=World.new("res://content/home-v3/world.json")
		w.residents.provision(w);w.library=library;library.configure(directory)
		check(Opening.apply(w,library,opening).ok,"opening fixture")
		var geometry:Dictionary={}
		for id in ["home.house.01","home.house.02","home.house.03","home.house.04","home.house.05"]:
			var site:Dictionary=w.objects[id]
			geometry[id]={"position":site.position.duplicate(),"size":w.site_size(site),"door":w.interior.outside("room."+id) if w.interior.rooms().has("room."+id) else w.point(site)+Vector2(0,w.site_size(site).y/2+1.5)}
		var target:String=directory.path_join(opening)
		check(Save.save_world(w,target),"legacy optional-free save")
		var old=World.new("res://content/home-v3/world.json");old.residents.provision(old);old.library=library
		check(Save.load_world(old,target).ok,"legacy optional-free load")
		for id in geometry:
			check(not old.objects[id].has("house_appearance") and Appearance.enabled(old.objects[id]),"missing appearance defaults personal")
			old.objects[id]["house_appearance"]="classic" if id in ["home.house.01","home.house.03"] else "personal"
		check(Save.save_world(old,target),"save explicit appearance")
		var loaded=World.new("res://content/home-v3/world.json");loaded.residents.provision(loaded);loaded.library=library
		check(Save.load_world(loaded,target).ok,"load explicit appearance")
		for id in geometry:
			var site:Dictionary=loaded.objects[id]
			check(site.position==geometry[id].position and loaded.site_size(site)==geometry[id].size,"original coordinates and footprint retained")
			check((loaded.interior.outside("room."+id) if loaded.interior.rooms().has("room."+id) else loaded.point(site)+Vector2(0,loaded.site_size(site).y/2+1.5))==geometry[id].door,"original door retained")
			check(site.house_appearance==old.objects[id].house_appearance,"appearance retained")
		check(loaded.work.jobs.is_empty() and loaded._routes.is_empty(),"reload restores no routes or jobs")
	print("House appearance legacy and explicit save/reload geometry ",not failed)
