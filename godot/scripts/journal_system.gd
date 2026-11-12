class_name JournalSystem
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Persistent first discoveries, fed only at the real fishing commit point.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var entries: Array=[]
var discoveries: Dictionary={}
var maximums:Dictionary={}
var catalog_revision:=""

func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/journal.json"))
	if not valid_config(data):world.error=LocalText.text("system.journal_system.the_fish_journal_settings_are_invalid");return
	config=data
	for species in config.species:
		for color in config.colors:
			for size in config.sizes:
				entries.append({"id":key(species,color,size),"species_id":species,"color_id":color,"size_id":size,"species_name":label("species",species),"color_name":label("colors",color),"size_name":label("sizes",size)})
	catalog_revision=world.memories._canonical([config,entries]).sha256_text()

func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("title") is String or data.title.is_empty() or data.title.length()>40:return false
	if not number(data.get("page_limit"),32) or data.page_limit<1 or not number(data.get("page_size"),32) or data.page_size<1 or data.page_size>data.page_limit:return false
	for kind in ["species","colors","sizes"]:
		var ids: Variant=data.get(kind)
		if not ids is Array or ids.is_empty() or ids.size()>64:return false
		var seen: Dictionary={}
		for id in ids:
			if not id is String or seen.has(id) or not world.fishing.rules[kind].any(func(option):return option.id==id):return false
			seen[id]=true
		if ids.size()!=world.fishing.rules[kind].size():return false
	if data.species.size()*data.colors.size()*data.sizes.size()>4096 or not data.get("descriptions") is Dictionary or data.descriptions.size()!=data.species.size():return false
	for id in data.species:
		if not data.descriptions.get(id) is String or data.descriptions[id].is_empty() or data.descriptions[id].length()>100:return false
	return data.get("discovery_lines") is Array and not data.discovery_lines.is_empty() and data.discovery_lines.size()<=12 and data.discovery_lines.all(func(line):return line is String and not line.is_empty() and line.length()<=50)

func number(value: Variant,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=0 and value<=maximum
func label(kind: String,id: String) -> String:
	for option in world.fishing.rules[kind]:
		if option.id==id:return option.name
	return id
func key(species: String,color: String,size: String) -> String:return species+":"+color+":"+size
func valid_first(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=7 or not value.get("fish_id") is String or value.fish_id.length()!=29 or not value.fish_id.begins_with("fish-") or not value.fish_id.substr(5).is_valid_hex_number(false):return false
	for pair in [["species_id","species"],["color_id","colors"],["size_id","sizes"]]:
		if not value.get(pair[0]) is String or value[pair[0]] not in config[pair[1]]:return false
	if not value.get("source_id") is String or not world.fishing.known_water(value.source_id) or not world.catalog._number(value.get("caught_at")) or value.caught_at<=0 or value.caught_at>253402300799 or not world.catalog._number(value.get("scale")):return false
	for size in world.fishing.rules.sizes:
		if size.id==value.size_id:return value.scale>=size.min and value.scale<=size.max
	return false

func record_catch(fish_id: String) -> bool:
	var fish: Dictionary=world.fishing.fish.get(fish_id,{})
	if fish.is_empty() or fish.location not in ["pending","storage"] or (fish.location=="storage" and fish.owner_id!="human") or not world.actors.has(fish.owner_id):return false
	var job: Dictionary=world.work.jobs.get(fish.owner_id,{})
	if job.get("intent")!="fish" or not job.get("caught",false) or job.get("water_id")!=fish.source_id:return false
	var record: Dictionary={"fish_id":fish.id,"species_id":fish.species_id,"color_id":fish.color_id,"size_id":fish.size_id,"scale":fish.scale,"source_id":fish.source_id,"caught_at":fish.caught_at}
	if not valid_first(record):return false
	var own: Dictionary=discoveries.get(fish.owner_id,{})
	var combination:=key(fish.species_id,fish.color_id,fish.size_id)
	var peaks:Dictionary=maximums.get(fish.owner_id,{})
	peaks[fish.species_id]=maxf(float(peaks.get(fish.species_id,0)),float(fish.scale));maximums[fish.owner_id]=peaks
	world.revision+=1
	if own.has(combination):return false
	own[combination]=record.duplicate(true);discoveries[fish.owner_id]=own;world.revision+=1;return true

func revision(id: String) -> String:
	return world.memories._canonical([world.world_id,id,catalog_revision,discoveries.get(id,{}),maximums.get(id,{})]).sha256_text()
func summary(id: String) -> Dictionary:
	return {"discovered":discoveries.get(id,{}).size(),"total":entries.size(),"revision":revision(id),"tracking":"own_catches"}
func query(id: String,args: Dictionary={}) -> Dictionary:
	if not world.actors.has(id):return {"ok":false,"error":"unknown_resident"}
	if args.keys().any(func(name):return name not in ["species_id","color_id","size_id","status","offset","limit","revision"]):return {"ok":false,"error":"invalid_journal_query"}
	for pair in [["species_id","species"],["color_id","colors"],["size_id","sizes"]]:
		if args.has(pair[0]) and (not args[pair[0]] is String or args[pair[0]] not in config[pair[1]]):return {"ok":false,"error":"invalid_journal_filter"}
	if args.has("status") and args.status not in ["all","caught"]:return {"ok":false,"error":"invalid_journal_filter"}
	var offset: Variant=args.get("offset",0);var limit: Variant=args.get("limit",config.page_size)
	if not number(offset,entries.size()) or not number(limit,int(config.page_limit)) or limit<1:return {"ok":false,"error":"invalid_journal_page"}
	if args.has("revision") and (not args.revision is String or args.revision.length()!=64 or not args.revision.is_valid_hex_number(false)):return {"ok":false,"error":"invalid_journal_revision"}
	var filters:=args.duplicate();filters.erase("offset");filters.erase("limit");filters.erase("revision")
	var current: String=world.memories._canonical([revision(id),filters]).sha256_text()
	if (offset>0 and not args.has("revision")) or (args.has("revision") and args.revision!=current):return {"ok":false,"error":"stale_journal","revision":current}
	var own: Dictionary=discoveries.get(id,{})
	var selected: Array=[]
	for entry in entries:
		if ["species_id","color_id","size_id"].any(func(name):return args.has(name) and args[name]!=entry[name]):continue
		if args.get("status","all")=="caught" and not own.has(entry.id):continue
		var item: Dictionary=entry.duplicate(true);item["caught"]=own.has(entry.id);item["first_catch"]=own.get(entry.id,{}).duplicate(true);selected.append(item)
	return {"ok":true,"version":1,"self_actor_id":id,"world_id":world.world_id,"revision":current,"catalog_revision":catalog_revision,"discovered":own.size(),"catalog_total":entries.size(),"total":selected.size(),"offset":int(offset),"limit":int(limit),"next_offset":int(offset)+int(limit) if offset+limit<selected.size() else -1,"entries":selected.slice(int(offset),int(offset+limit)).duplicate(true)}

func saved() -> Dictionary:
	var result:Dictionary={"version":1,"discoveries":discoveries.duplicate(true)}
	if not maximums.is_empty():result.maximums=maximums.duplicate(true)
	return result
func restore(data: Dictionary) -> void:
	discoveries=data.get("discoveries",{}).duplicate(true);maximums=data.get("maximums",{}).duplicate(true)
func valid_saved(data: Variant,actors: Dictionary) -> bool:
	if not data is Dictionary or data.size() not in [2,3] or data.keys().any(func(k):return k not in ["version","discoveries","maximums"]) or not valid_maximums(data.get("maximums",{}),actors) or data.get("version")!=1 or not data.get("discoveries") is Dictionary or data.discoveries.size()>actors.size():return false
	var seen_fish: Dictionary={}
	for id in data.discoveries:
		if not actors.has(id) or not data.discoveries[id] is Dictionary or data.discoveries[id].size()>entries.size():return false
		for combination in data.discoveries[id]:
			var first: Variant=data.discoveries[id][combination]
			if not valid_first(first) or combination!=key(first.species_id,first.color_id,first.size_id) or seen_fish.has(first.fish_id):return false
			seen_fish[first.fish_id]=true
	return true

func maximum(id:String,species:String)->float:
	var result:float=float(maximums.get(id,{}).get(species,0))
	for first in discoveries.get(id,{}).values():
		if first.species_id==species:result=maxf(result,float(first.scale))
	return result
func valid_maximums(value:Variant,actors:Dictionary)->bool:
	if not value is Dictionary or value.size()>actors.size():return false
	for id in value:
		if not actors.has(id) or not value[id] is Dictionary or value[id].size()>config.species.size():return false
		for species in value[id]:
			var n:Variant=value[id][species]
			if species not in config.species or not world.catalog._number(n) or n<1 or n>8:return false
	return true
