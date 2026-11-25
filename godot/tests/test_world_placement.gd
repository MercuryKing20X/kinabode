extends SceneTree

const Save=preload("res://scripts/save_store.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")
class Stub extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_payload:Dictionary)->bool:return false

var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1;push_error(label)

func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	if not (data.begins_with("/tmp/") or data.begins_with("/var/folders/")):quit(2);return
	set_meta("title_opening","showcase")
	Pool.obtain(self,data).factory=func(_id):return Stub.new()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
	root.add_child(game)
	game.set_process(false);game.save_enabled=false
	var w:RefCounted=game.world
	var layer:RefCounted=w.flower_creation.creations
	var catalog:Dictionary=layer.catalog()
	check(catalog.size()>=30 and catalog.values().filter(func(row):return not row.walkable).size()>=4,"full catalog")
	var original:=["path","bench","lamp","sign","fence","fence_vertical","rock","sapling","table","barrel"]
	var center:Vector2=w.point(w.actors.human).round()
	var cells:Array[Vector2]=[]
	for y in range(-12,13):
		for x in range(-12,13):
			cells.append(center+Vector2(x,y))
	cells.sort_custom(func(a,b):return a.distance_squared_to(center)<b.distance_squared_to(center))
	var saved_pieces:Array[Dictionary]=[]
	for item in original:
		var did_place:=false
		for tries in 20:
			# Only search the cells this fixture actually needs. Commit still
			# validates each item and key-point rejection is asserted below.
			while not cells.is_empty() and not layer.check("human","place_piece",{"item":"fence","position":[cells[0].x,cells[0].y]}).is_empty():
				cells.pop_front()
			if cells.is_empty():break
			var p:Vector2=cells.pop_front()
			var args:Dictionary={"item":item,"position":[p.x,p.y],"label":"样板 "+str(item)}
			if not move(w,layer,p):continue
			var before:int=w.storage.count("wood")
			if layer.commit("human","place_piece",args,"")!="":continue
			var cost:int=catalog[item].material.wood
			check(w.storage.count("wood")==before-cost and w.walkable("home",p)==catalog[item].walkable,"debit and collision "+item)
			check(layer.commit("human","name_place",args,"")=="","naming "+item)
			check(layer.commit("human","remove_piece",args,"")=="" and w.storage.count("wood")==before-cost+floori(cost/2.0) and w.walkable("home",p),"refund and collision cleared "+item)
			check(layer.commit("human","place_piece",args,"")=="" and layer.commit("human","name_place",args,"")=="","replace and name "+item)
			saved_pieces.append(args)
			did_place=true;break
		check(did_place,"route to a placement cell for "+item)
		# Retain the receipts and test a common aggregate save separately from the
		# ten purchase/refund cycles, using the opening's actual wood.
		if did_place and w.storage.count("wood")<5 and saved_pieces.size()<original.size():
			check(haul(w),"real wood hauling tops up showcase stock")
	for locale in ["zh","en"]:
		TranslationServer.set_locale(locale)
		var points:Dictionary=layer.key_points()
		for needle in (["门口","仓库","营火","码头","桥"] if locale=="zh" else [" door","Warehouse","campfire","pier","bridge"]):
			var name:Variant=points.keys().filter(func(key):return needle in key).front()
			var p:Vector2=points[name].round()
			var refusal:Dictionary=layer.check("human","place_piece",{"item":"fence","position":[p.x,p.y]},true)
			check(refusal.get("error")=="blocks_access" and name in refusal.get("message","") and "%s" not in refusal.get("message",""),"localized access refusal "+locale+" "+needle)
		var point:Vector2=points.values()[0]
		check(layer.commit("human","remove_piece",{"position":[point.x,point.y]},"")=="protected_or_missing","original structure protected "+locale)
	var old:Dictionary=layer.pieces.duplicate(true)
	check(old.size()==original.size(),"all ten pieces present at save")
	check(Save.save_world(w,data),"world saves")
	layer.restore({})
	var loaded:Dictionary=Save.load_world(w,data)
	check(loaded.get("loaded",false) and layer.pieces==JSON.parse_string(JSON.stringify(old)),"all pieces, names and owners restore: "+str(loaded.get("error","")))
	print("WORLD_PLACEMENT checks=",checks," failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

func move(w:RefCounted,layer:RefCounted,p:Vector2)->bool:
	if not w._apply_route("human",layer.approach("human",p)):return false
	for i in 400:
		if not w._routes.has("human"):return w.point(w.actors.human).distance_to(p)<=2
		w.advance(.1)
	return false

func haul(w:RefCounted)->bool:
	var before:int=w.storage.count("wood")
	if not w.gathering.start("human",{"intent":"gather_wood","tree_count":3}).ok:return false
	for i in 1500:
		w.advance(.1)
		if not w.work.jobs.has("human") and not w._routes.has("human"):return w.storage.count("wood")>before
	return false
