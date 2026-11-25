extends RefCounted

const Config=preload("res://scripts/island_note_rules.gd")
var owner:WeakRef
var w:RefCounted:
	get:return owner.get_ref()
var rows:Dictionary={}
var gifts:Dictionary={}
var first:Dictionary={}
var last_write:Dictionary={}
var serial:=0

func _init(world:RefCounted)->void:owner=weakref(world)

static func valid_text(value:Variant)->bool:
	if not value is String or value.length()>120 or value.strip_edges().is_empty():return false
	for i in value.length():
		var code:int=value.unicode_at(i)
		if code<32 or code in [127,8232,8233] or code>=8234 and code<=8238 or code>=8294 and code<=8297:return false
	return preload("res://scripts/persona_cards.gd").safe_speech(value)

func tick()->void:
	for id in rows.keys():
		if w.days.day()>=int(rows[id].day)+Config.DAYS:
			rows.erase(id);w.revision+=1

func write(id:String,recipient:String,at:String,line:Variant,english:Variant="")->String:
	if id=="human" or not w.director.brains.has(id) or not valid_text(line) or not valid_text(english):return "invalid_note_text"
	if not w.actors.has(recipient) or recipient==id:return "invalid_recipient"
	if rows.size()>=Config.MAX_NOTES or w.forest.clock<float(last_write.get(id,-Config.INTERVAL))+Config.INTERVAL:return "note_limit"
	var anchors:Dictionary=places()
	if not anchors.has(at) or w.actors[id].region_id!="home" or w.point(w.actors[id]).distance_to(anchors[at])>2:return "not_at_note_spot"
	serial+=1
	var p:Vector2=anchors[at]
	var key:String="island-note:"+str(serial)
	rows[key]={"id":key,"author":id,"recipient":recipient,"day":w.days.day(),"position":[p.x,p.y],"text":line,"en":english,"read":false}
	last_write[id]=w.forest.clock;w.revision+=1
	return ""

func first_fact(kind:String,author:String)->void:
	if first.has(kind):return
	if w.memories.record_event(kind,kind,[author,"human"],{"actor_id":author}):
		first[kind]=author;w.revision+=1

func read_note(id:String,recipient:String)->Dictionary:
	var row:Dictionary=rows.get(id,{})
	if row.is_empty() or row.recipient!=recipient:return {}
	if not row.read:row.read=true;w.revision+=1
	if recipient=="human":
		if not first.has("doorstep_note_first") and w.memories.record_event("doorstep_note_first","doorstep_note_first",["human",row.author],{"actor_id":row.author}):
			first["doorstep_note_first"]=row.author;w.revision+=1
	return row.duplicate(true)

func places()->Dictionary:
	var result:Dictionary={}
	for site in w.objects.values():
		if site.region_id!="home" or site.kind!="construction_site" or int(site.get("stage_index",0))<5:continue
		if site.id==w.standard.config.get("house",{}).get("site_id","home.house.01"):
			var spot:Vector2=w.interior.outside(w.interior.room_for(site.id))
			if not w.walkable("home",spot):spot=w.nearest_walkable("home",spot)
			if spot.is_finite():result["doorstep"]=spot;break
	if w.standard.ready("home.barbecue") and w.barbecues.has("home.barbecue"):
		var fire:Dictionary=w.barbecues["home.barbecue"].station
		var spot:Vector2=w.nearest_walkable("home",w.point(fire)+Vector2(1,2))
		if spot.is_finite():result["campfire"]=spot
	for seat in w.leisure.sites.values():
		if seat.get("complete",false) and seat.region_id=="home" and seat.get("template_id")=="play-bench" and not str(seat.id).begins_with("play.standard."):
			var spot:Vector2=w.nearest_walkable("home",w.point(seat)+Vector2(0,1))
			if spot.is_finite():result["bench"]=spot;break
	return result

func drop_gift(id:String,item:String)->String:
	var actor:Dictionary=w.actors[id]
	var at:Vector2=places().get("doorstep",Vector2.INF)
	if not at.is_finite() or actor.region_id!="home" or w.point(actor).distance_to(at)>2:return "not_at_doorstep"
	if gifts.size()>=Config.MAX_NOTES or gifts.values().any(func(row):return row.author==id):return "doorstep_occupied"
	var fish:Dictionary=w.fishing.held(id)
	if not fish.is_empty() and fish.id==item:w.fishing.move_fish(fish,"doorstep")
	else:
		if item not in Config.ROSES or int(actor.carry.get(item,0))<1:return "insufficient_owned_items"
		preload("res://scripts/carry_retention.gd").consume(actor,item,1)
		actor.carry[item]=int(actor.carry[item])-1
		if actor.carry[item]==0:actor.carry.erase(item)
	serial+=1
	var key:String="island-gift:"+str(serial)
	gifts[key]={"id":key,"author":id,"position":[at.x,at.y],"item":item}
	first_fact("doorstep_gift_first",id)
	w.revision+=1
	return ""

func collect(id:String)->bool:
	var row:Dictionary=gifts.get(id,{})
	if row.is_empty() or w.actors.human.region_id!="home" or w.point(w.actors.human).distance_to(w.point(row))>1.4 or w.work.jobs.has("human"):return false
	if str(row.item).begins_with("fish-"):
		var fish:Dictionary=w.fishing.fish.get(row.item,{})
		if fish.get("location")!="doorstep" or fish.get("owner_id")!=row.author:return false
		w.fishing.move_fish(fish,"storage","human")
	elif not w.storage.add({row.item:1}):return false
	gifts.erase(id);w.revision+=1
	return true

func saved()->Dictionary:return {"notes":rows.duplicate(true),"gifts":gifts.duplicate(true),"first":first.duplicate(),"last_write":last_write.duplicate(),"serial":serial}

func restore(data:Dictionary)->void:
	rows=data.get("notes",{}).duplicate(true)
	gifts=data.get("gifts",{}).duplicate(true)
	first=data.get("first",{}).duplicate()
	last_write=data.get("last_write",{}).duplicate()
	serial=int(data.get("serial",0))

func valid(data:Variant,actors:Dictionary,fish:Dictionary)->bool:
	if not data is Dictionary or data.size()!=5 or not data.get("notes") is Dictionary or not data.get("gifts") is Dictionary or not data.get("first") is Dictionary or not data.get("last_write") is Dictionary or not whole(data.get("serial"),1000000000) or data.notes.size()>Config.MAX_NOTES or data.gifts.size()>Config.MAX_NOTES:return false
	for kind in data.first:
		if kind not in ["doorstep_note_first","doorstep_gift_first"] or data.first[kind]=="human" or not actors.has(data.first[kind]):return false
	for id in data.last_write:
		if id=="human" or not actors.has(id) or not number(data.last_write[id]) or data.last_write[id]<0:return false
	for id in data.notes:
		var row:Variant=data.notes[id]
		if not row is Dictionary or row.size()!=8 or not row.get("read") is bool or not id.begins_with("island-note:") or row.get("id")!=id:return false
		var n:String=id.trim_prefix("island-note:")
		if not n.is_valid_int() or int(n)<1 or int(n)>data.serial or str(int(n))!=n:return false
		if row.get("author")=="human" or not actors.has(row.get("author")) or not actors.has(row.get("recipient")) or row.author==row.recipient:return false
		if not whole(row.get("day"),1000000) or row.day<1 or not valid_text(row.get("text")) or not valid_text(row.get("en")):return false
		if not valid_position(row):return false
	var authors:Dictionary={}
	var presented:Dictionary={}
	for id in data.gifts:
		var row:Variant=data.gifts[id]
		if not row is Dictionary or row.size()!=4 or not id.begins_with("island-gift:") or row.get("id")!=id:return false
		var n:String=id.trim_prefix("island-gift:")
		if not n.is_valid_int() or int(n)<1 or int(n)>data.serial or str(int(n))!=n or data.notes.has("island-note:"+n):return false
		if row.get("author")=="human" or not actors.has(row.get("author")) or authors.has(row.author) or not row.get("item") is String or not valid_position(row):return false
		if row.item not in Config.ROSES:
			var instance:Variant=fish.get(row.item,{})
			if not instance is Dictionary or instance.get("location")!="doorstep" or instance.get("owner_id")!=row.author or presented.has(row.item):return false
			presented[row.item]=true
		authors[row.author]=true
	for id in fish:
		if fish[id] is Dictionary and fish[id].get("location")=="doorstep" and not presented.has(id):return false
	return true

func valid_position(row:Dictionary)->bool:
	if not row.get("position") is Array or row.position.size()!=2 or not row.position.all(number):return false
	var p:Vector2=w.point(row)
	var region:Dictionary=w.region_info("home")
	return Rect2(w.catalog.local_origin(region),Vector2(region.size[0],region.size[1])).has_point(p)

static func number(n:Variant)->bool:return (n is int or n is float) and is_finite(n)
static func whole(n:Variant,maximum:int)->bool:return number(n) and n>=0 and n<=maximum and floor(n)==n
