extends RefCounted
signal entry_deleted(entry:Dictionary)
const Text=preload("res://scripts/localization.gd")
var life_archive_ref:WeakRef
var directory:=""
var entries:Dictionary={}
var deleted:Dictionary={}
var card_limit:=2200
var error:=""
var dirty_daily:Dictionary={}
var latest_ai:Dictionary={}
var quote_limit:=64
func setup(base:String)->bool:
	var config:Variant=decode(FileAccess.get_file_as_string("res://content/memory-books.json"))
	if config is Dictionary:
		card_limit=clampi(int(config.get("card_chars",2200)),256,4000)
		quote_limit=clampi(int(config.get("ai_quote_limit",64)),1,256)
	directory=base.path_join("memories")
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return false
	var dirty:Variant=read_json(directory.path_join("dirty-daily.json"))
	if dirty is Dictionary:dirty_daily=dirty
	var tomb:Variant=read_json(directory.path_join("deleted.json"))
	if tomb is Dictionary:deleted=tomb
	for name in DirAccess.get_files_at(directory):
		if not name.ends_with(".entry.json"):continue
		var value:Variant=read_json(directory.path_join(name))
		if not valid(value) and FileAccess.file_exists(directory.path_join(name)+".bak"):value=decode(FileAccess.get_file_as_string(directory.path_join(name)+".bak"))
		if valid(value) and not deleted.has(value.id):entries[value.id]=value
	return true
func decode(text:String)->Variant:
	var parser:=JSON.new()
	return parser.data if parser.parse(text)==OK else null
func read_json(path:String)->Variant:
	var value:Variant=decode(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if value==null and FileAccess.file_exists(path+".bak"):value=decode(FileAccess.get_file_as_string(path+".bak"))
	return value
func atomic(path:String,value:Variant)->bool:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(value));file.flush();file.close()
	if FileAccess.file_exists(path):
		var old:Variant=decode(FileAccess.get_file_as_string(path))
		if old!=null:DirAccess.copy_absolute(path,path+".bak")
	return DirAccess.rename_absolute(path+".tmp",path)==OK
func valid(value:Variant)->bool:
	if not value is Dictionary or JSON.stringify(value).to_utf8_buffer().size()>65536:return false
	for field in ["resident_id","world_id","event_id","text","source"]:
		if not value.get(field) is String:return false
	if not value.get("id") is String or value.id.length()!=64 or not value.id.is_valid_hex_number(false):return false
	if not value.get("photo_id","") is String:return false
	if value.get("layer") not in ["facts","about_you","feelings","letters","daily"] or not value.get("participants") is Array or not value.get("params") is Dictionary:return false
	for field in ["day","at"]:
		if not (value.get(field) is int or value.get(field) is float) or not is_finite(value[field]) or value[field]<0:return false
	return value.day==floor(value.day) and value.text.length()<=12000 and value.participants.all(func(id):return id is String)
func add(resident:String,world_id:String,event_id:String,layer:String,text:String,params:Dictionary={},day:int=1,source:String="game",participants:Array=[],at:float=0.0)->bool:
	var id:String=(resident+"|"+world_id+"|"+event_id+"|"+layer).sha256_text()
	if entries.has(id) or deleted.has(id):return false
	var entry:Dictionary={"id":id,"resident_id":resident,"world_id":world_id,"event_id":event_id,"layer":layer,"text":text,"params":params.duplicate(true),"day":day,"at":Time.get_unix_time_from_system() if at<=0 else at,"source":source,"participants":participants.duplicate(),"photo_id":""}
	if directory.is_empty() or not valid(entry) or not atomic(directory.path_join(id+".entry.json"),entry):return false
	entries[id]=entry;return true
func remove(id:String)->bool:
	if not entries.has(id):
		var changed:=false
		for key in entries.keys():
			if not entries.has(key):continue
			var entry:Dictionary=entries[key]
			if entry.params.get("archive_summary",false) and entry.params.quotes.has(id):
				var next_entry:Dictionary=entry.duplicate(true);next_entry.params.quotes.erase(id);next_entry.params.source_ids=next_entry.params.quotes.keys()
				if next_entry.params.quotes.is_empty():remove(key)
				elif atomic(directory.path_join(key+".entry.json"),next_entry):entries[key]=next_entry
				changed=true
		return changed
	var next:Dictionary=deleted.duplicate();next[id]=true
	if not atomic(directory.path_join("deleted.json"),next):return false
	var erased:Dictionary=entries[id].duplicate(true)
	if erased.layer=="daily":
		dirty_daily[erased.resident_id+":"+erased.world_id+":"+str(erased.day)]={"resident_id":erased.resident_id,"world_id":erased.world_id,"day":erased.day}
		atomic(directory.path_join("dirty-daily.json"),dirty_daily)
	deleted=next;entries.erase(id)
	entry_deleted.emit(erased)
	# Derived summaries are invalidated, never used after a source is removed.
	for key in entries.keys():
		if entries.has(key) and id in entries[key].params.get("source_ids",[]):remove(key)
	if erased.layer=="about_you" and erased.params.get("kind","")!="portrait":
		for source_id in erased.params.get("source_ids",[]):remove(source_id)
	return true
func list_for(resident:String,layer:String="")->Array:
	var result:Array=entries.values().filter(func(e):return e.resident_id==resident and (layer.is_empty() or e.layer==layer))
	result.sort_custom(func(a,b):return a.at<b.at if a.at!=b.at else a.id<b.id)
	return result.duplicate(true)
func render(entry:Dictionary)->String:
	if entry.text=="memory.localized_fact":return str(entry.params.localized.get("en" if Text.revision().begins_with("en") else "zh",""))
	if entry.params.get("archive_summary",false):
		var quotes:Array=entry.params.quotes.values().map(func(value):return str(value))
		return Text.text("memory.daily_chat").replace("{count}",str(quotes.size()))+" · "+" / ".join(quotes)
	var line:String=Text.text(entry.text) if Text.entries.has(entry.text) else entry.text
	for key in entry.params:line=line.replace("{"+str(key)+"}",str(entry.params[key]))
	return line
func card(resident:String,query:String="",channel:String="",level:String="")->Dictionary:
	var life:bool=level=="lifeblood"
	var limit:int=10000 if life else card_limit
	var all:Array=list_for(resident)
	if channel=="group:all":
		all=all.filter(func(e):return e.params.get("channel","")=="group:all" or (e.layer=="facts" and not e.params.get("human_quote",false)))
	var summaries:Array=all.filter(func(e):return e.layer=="daily")
	var latest_days:Array=[]
	for e in summaries:
		var day_key:String=e.world_id+":"+str(e.day)
		if day_key in latest_days:latest_days.erase(day_key)
		latest_days.append(day_key)
	latest_days=latest_days.slice(-30 if life else -3)
	var days:Array=summaries.filter(func(e):return e.world_id+":"+str(e.day) in latest_days)
	var about:Array=all.filter(func(e):return e.layer=="about_you")
	if not life:about=about.slice(-10)
	var facts:Array=all.filter(func(e):return e.layer=="facts")
	var relevant:Array=facts.duplicate()
	if query.is_empty():relevant.reverse()
	else:
		var scores:Dictionary={}
		for fact in facts:scores[fact.id]=relevance(fact,query)
		relevant.sort_custom(func(a,b):
			var sa:float=scores[a.id];var sb:float=scores[b.id]
			return a.at>b.at if sa==sb else sa>sb)
	var result:Dictionary={"daily":[],"about_you":[],"facts":[]};
	if life:result.important=[]
	var used:=0
	for pair in [["daily",days],["about_you",about],["facts",relevant.slice(0,20 if life else 5)],["important",all.filter(func(e):return life and (e.layer=="letters" or e.params.get("kind","")=="weekly" or e.event_id.begins_with("anniversary:") or e.text=="memory.first_fish")).slice(-12)]]:
		var section_used:=0
		var quota:int={"daily":3000,"about_you":2200,"facts":3000,"important":1800}.get(pair[0],0) if life else limit
		for e in pair[1]:
			var text:String=render(e)
			if life:text=text.left(96 if pair[0]=="about_you" else 36 if pair[0]=="daily" else 86 if pair[0]=="facts" else 180)
			var cost:int=text.length()+64
			if used+cost>limit or section_used+cost>quota or not result.has(pair[0]):continue
			result[pair[0]].append({"id":e.id,"text":text});used+=cost;section_used+=cost
	return result
func relevance(entry:Dictionary,query:String)->float:
	var text:String=(render(entry)+" "+JSON.stringify(entry.params)+" "+" ".join(entry.participants)).to_lower()
	var q:String=query.to_lower()
	for group_text in Text.source("life.synonyms").split(";"):
		var group:Array=Array(group_text.split("|"))
		if group.any(func(w):return q.contains(w)):
			for word in group:q+=" "+word
	var score:=0.0
	var seen:Dictionary={}
	for i in range(q.length()):
		var word:String=q.substr(i,2)
		if word.strip_edges().length()<2 or seen.has(word):continue
		seen[word]=true
		if text.contains(word):score+=8.0 if query.to_lower().contains(word) else 2.0
	for person in entry.participants:
		if q.contains(person):score+=8.0
	if q.contains(str(entry.day)):score+=1.0
	return score

func migrate(world:RefCounted)->Dictionary:
	var counts:Dictionary={};world.memories.sync()
	for raw in world.memories.records:
		var count:int=ingest(world,raw)
		if count>0:counts[raw.kind]=int(counts.get(raw.kind,0))+count
	for actor in world.journal.discoveries:
		for key in world.journal.discoveries[actor]:
			if actor=="human":continue
			var fact:Dictionary=world.journal.discoveries[actor][key]
			if add(actor,world.world_id,"journal:"+key,"facts","memory.first_fish",{"fish":key,"legacy":fact},world.days.day(),"game",[actor],float(fact.caught_at)):counts.journal=int(counts.get("journal",0))+1
	return counts
func ingest(world:RefCounted,raw:Dictionary,legacy:bool=true)->int:
	var count:=0
	var described:Dictionary=world.memories._describe(raw)
	var params:Dictionary={"legacy":raw.duplicate(true)}
	if not legacy:params["localized"]={"zh":world.memories._describe(raw,"zh").summary,"en":world.memories._describe(raw,"en").summary}
	for actor in raw.participants:
		if actor=="human":continue
		if add(actor,raw.world_id,raw.id,"facts",str(described.summary) if legacy else "memory.localized_fact",params,0 if legacy else world.days.day(),"game",raw.participants,raw.occurred_at):count+=1
	return count
func remember_chat(resident:String,world_id:String,event_id:String,text:String,day:int,channel:String="")->void:
	add(resident,world_id,event_id,"facts",text,{"human_quote":true,"channel":channel},day,"local",["human",resident])
	if text.begins_with(Text.source("memory.like_prefix")) or text.to_lower().begins_with("i like "):
		add(resident,world_id,event_id,"about_you",text,{"human_quote":true,"channel":channel,"source_ids":[(resident+"|"+world_id+"|"+event_id+"|facts").sha256_text()]},day,"local",["human",resident])
	var quotes:Array=list_for(resident).filter(func(e):return e.params.get("human_quote",false))
	while quotes.size()>2000:
		var old:Dictionary=quotes.pop_front()
		if not archive_quote(old):break
func archive_quote(old:Dictionary)->bool:
	var candidates:Array=list_for(old.resident_id,"daily").filter(func(e):return e.world_id==old.world_id and e.day==old.day and e.params.get("channel","")==old.params.get("channel","") and e.params.get("archive_summary",false) and e.params.quotes.size()<32)
	var summary:Dictionary
	if candidates.is_empty():
		var event_id:String="chat-summary:"+Crypto.new().generate_random_bytes(12).hex_encode()
		if not add(old.resident_id,old.world_id,event_id,"daily","memory.daily_chat",{"archive_summary":true,"quotes":{},"source_ids":[],"channel":old.params.get("channel","")},int(old.day),"local",old.participants,old.at):return false
		summary=entries[(old.resident_id+"|"+old.world_id+"|"+event_id+"|daily").sha256_text()].duplicate(true)
	else:summary=candidates[-1].duplicate(true)
	summary.params.quotes[old.id]=str(old.text).left(80)+("…" if str(old.text).length()>80 else "")
	summary.params.source_ids=summary.params.quotes.keys()
	if not atomic(directory.path_join(summary.id+".entry.json"),summary):return false
	entries[summary.id]=summary
	# Retention is not a player deletion: keep independently retained preferences.
	var next:Dictionary=deleted.duplicate();next[old.id]=true
	if not atomic(directory.path_join("deleted.json"),next):return false
	deleted=next;entries.erase(old.id)
	DirAccess.remove_absolute(directory.path_join(old.id+".entry.json"))
	return true

func export_html(path:String,include_quotes:bool=true)->bool:
	var html:="<!doctype html><meta charset='utf-8'><title>"+Text.text("memory.album").xml_escape()+"</title><style>body{max-width:900px;margin:3em auto;background:#fff6e5;color:#352b30;font:18px sans-serif}article{padding:1em;border-bottom:1px solid #ccb}nav{position:sticky;top:0;background:#fff6e5}</style>"
	var residents:Array=[]
	for e in entries.values():
		if e.resident_id not in residents:residents.append(e.resident_id)
	var day_values:Array=entries.values().map(func(e):return int(e.day))
	html+="<style>.cover,.page{min-height:80vh;padding:3em;box-shadow:0 4px 18px #4323;background:#fffdf5;margin:2em 0}.letter{border:1px dashed #a98;padding:2em}img{max-width:100%;image-rendering:pixelated}h2{break-before:page}</style><section class=cover><h1>"+Text.text("life.cover").xml_escape()+"</h1><p>"+str(day_values.min() if not day_values.is_empty() else 0)+" — "+str(day_values.max() if not day_values.is_empty() else 0)+"</p><p>"+Text.text("life.friends").xml_escape()+"</p></section><nav>"
	for resident in residents:html+="<a href='#"+str(resident).xml_escape()+"'>"+display_name(str(resident)).xml_escape()+"</a> · "
	html+="</nav>"
	for resident in residents:
		html+="<h1 id='"+str(resident).xml_escape()+"'>"+display_name(str(resident)).xml_escape()+"</h1>"
		var notes:Array=list_for(resident,"about_you")
		html+="<h2>"+Text.text("memory.portrait").xml_escape()+"</h2><p>"+" / ".join(notes.filter(func(e):return include_quotes or not e.params.get("human_quote",false)).map(func(e):return render(e).xml_escape()))+"</p>"
		var page_day:=-1
		for e in list_for(resident):
			if int(e.day)!=page_day:
				if page_day>=0:html+="</section>"
				page_day=int(e.day);html+="<section class=page><h2>Day "+str(page_day)+"</h2>"
			if not include_quotes and (e.params.get("human_quote",false) or e.params.get("archive_summary",false) or e.text=="memory.chat_summary"):continue
			html+="<article class='"+("letter" if e.layer=="letters" else "entry")+"'><small>"+("✦ " if e.event_id.begins_with("anniversary:") else "")+Time.get_datetime_string_from_unix_time(int(e.at))+" · "+str(e.layer).xml_escape()+"</small><p>"+render(e).xml_escape()+"</p>"+photo_html(str(e.get("photo_id","")))+photo_html(str(e.params.get("attachment","")))+"</article>"
		if page_day>=0:html+="</section>"
	return atomic_text(path,html)
func atomic_text(path:String,text:String)->bool:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(text);file.close();return DirAccess.rename_absolute(path+".tmp",path)==OK
func export_data(path:String)->bool:
	var crypto:=Crypto.new();var key:=CryptoKey.new();var key_path:String=directory.path_join("signing.key")
	if FileAccess.file_exists(key_path):
		if key.load(key_path)!=OK:return false
	else:
		key=crypto.generate_rsa(2048)
		if key==null or key.save(key_path)!=OK:return false
	var photos:Dictionary={}
	for e in entries.values():
		for relative in [str(e.get("photo_id","")),str(e.params.get("attachment",""))]:
			var photo:String=photo_path(relative)
			if not photo.is_empty() and FileAccess.file_exists(photo) and FileAccess.get_file_as_bytes(photo).size()<=1048576:photos[relative]=Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(photo))
	var payload:String=JSON.stringify({"entries":entries.values(),"deleted":deleted,"photos":photos,"life":life_archive_ref.get_ref().export_bundle() if life_archive_ref!=null and is_instance_valid(life_archive_ref.get_ref()) else {}})
	var digest:PackedByteArray=payload.sha256_buffer()
	return atomic(path,{"version":1,"payload":payload,"sha256":digest.hex_encode(),"public_key":key.save_to_string(true),"signature":Marshalls.raw_to_base64(crypto.sign(HashingContext.HASH_SHA256,digest,key))})
func import_data(path:String)->Dictionary:
	var selected:=FileAccess.open(path,FileAccess.READ)
	if selected==null or selected.get_length()>268435456:return {"ok":false,"error":"file"}
	var bundle:Variant=decode(selected.get_as_text());selected.close()
	if not bundle is Dictionary or bundle.get("version")!=1 or not bundle.get("payload") is String:return {"ok":false,"error":"format"}
	var digest:PackedByteArray=bundle.payload.sha256_buffer();var key:=CryptoKey.new()
	if digest.hex_encode()!=bundle.get("sha256") or key.load_from_string(str(bundle.get("public_key","")),true)!=OK or not Crypto.new().verify(HashingContext.HASH_SHA256,digest,Marshalls.base64_to_raw(str(bundle.get("signature",""))),key):return {"ok":false,"error":"signature"}
	var data:Variant=decode(bundle.payload)
	if not data is Dictionary or not data.get("entries") is Array or not data.get("deleted") is Dictionary or not data.entries.all(valid):return {"ok":false,"error":"entries"}
	var life_data:Variant=data.get("life",{})
	var archive:Variant=life_archive_ref.get_ref() if life_archive_ref!=null else null
	if not life_data is Dictionary or (not life_data.is_empty() and (not is_instance_valid(archive) or not archive.valid_bundle(life_data))):return {"ok":false,"error":"life"}
	for id in data.deleted:
		if not id is String or id.length()!=64 or not id.is_valid_hex_number(false) or data.deleted[id]!=true:return {"ok":false,"error":"deletions"}
	var imported_photos:Variant=data.get("photos",{})
	if not imported_photos is Dictionary or imported_photos.size()>10000:return {"ok":false,"error":"photos"}
	for relative in imported_photos:
		if not relative is String or photo_path(relative).is_empty() or not imported_photos[relative] is String or imported_photos[relative].length()>1398104:return {"ok":false,"error":"photos"}
		var bytes:PackedByteArray=Marshalls.base64_to_raw(imported_photos[relative]);var image:=Image.new()
		if image.load_png_from_buffer(bytes)!=OK or image.get_width()!=320 or image.get_height()!=200:return {"ok":false,"error":"photos"}
	for relative in imported_photos:
		var photo:String=photo_path(relative)
		DirAccess.make_dir_recursive_absolute(photo.get_base_dir())
		var image:=Image.new();image.load_png_from_buffer(Marshalls.base64_to_raw(imported_photos[relative]))
		if image.save_png(photo+".tmp")!=OK or DirAccess.rename_absolute(photo+".tmp",photo)!=OK:return {"ok":false,"error":"write"}
	var tombstones:Dictionary=deleted.duplicate()
	tombstones.merge(data.deleted,true)
	if not atomic(directory.path_join("deleted.json"),tombstones):return {"ok":false,"error":"write"}
	deleted=tombstones
	for id in data.deleted:
		if entries.has(id):
			var removed:Dictionary=entries[id].duplicate(true);entries.erase(id);entry_deleted.emit(removed)
	var count:=0
	for e in data.entries:
		if entries.has(e.id) or deleted.has(e.id) or data.deleted.has(e.id):continue
		if not atomic(directory.path_join(e.id+".entry.json"),e):return {"ok":false,"error":"write","count":count}
		entries[e.id]=e;count+=1
	if is_instance_valid(archive) and not archive.import_bundle(life_data):return {"ok":false,"error":"life_write","count":count}
	return {"ok":true,"count":count}

func display_name(resident:String)->String:
	return Text.text({"codex":"resident.snow","companion-2":"resident.skye","npc.mira":"resident.clem","npc.nora":"resident.raven"}.get(resident,"resident.unknown"))

func letter_has_system_words(text:String)->bool:
	var normalized:=text.to_lower().replace(" ", "").replace("\t", "")
	var words:Array=Array(Text.source("memory.letter_system_terms").split("|"))
	words.append_array(["source_id","sourceid","quoteid","citationid","system","notes"])
	for word in words:
		if normalized.contains(word):return true
	return false

# Only the bound host reply path calls this, with exactly the source IDs sent in that turn.
func accept_ai(resident:String,world_id:String,provider:String,writes:Variant,allowed:Array,day:int,request:Dictionary={}) -> Dictionary:
	var result:Dictionary={"accepted":0,"rejected":0}
	if provider.is_empty() or not writes is Array or writes.size()>6:return {"accepted":0,"rejected":1}
	for item in writes:
		if not item is Dictionary or item.keys().any(func(k):return k not in ["layer","text","source_ids","kind","target_id"]):result.rejected+=1;continue
		var layer:String=str(item.get("layer",""));var text:String=str(item.get("text","")).strip_edges();var ids:Variant=item.get("source_ids",[])
		if layer=="letters" and letter_has_system_words(text):result.rejected+=1;continue
		if layer not in ["about_you","feelings","letters","daily"] or text.is_empty() or text.length()>1200 or not ids is Array or ids.is_empty() or ids.size()>24:result.rejected+=1;continue
		var sources:Array=[]
		for id in ids:
			if id is String and id in allowed and entries.has(id) and entries[id].resident_id==resident and entries[id].world_id==world_id:sources.append(entries[id])
		if sources.size()!=ids.size():result.rejected+=1;continue
		if item.get("kind","")=="wish":
			var goals:Array=request.get("goals",[]).filter(func(g):return g.id==item.get("target_id"))
			if goals.is_empty() or list_for(resident,"facts").any(func(e):return e.world_id==world_id and e.params.get("goal_status","") in ["offered","accepted"] and e.params.get("expires",0)>=day):result.rejected+=1;continue
			var goal:Dictionary=goals[0]
			if add(resident,world_id,"goal-offer:"+str(day),"facts","memory.goal_offer",{"goal_status":"offered","farm_id":goal.id,"farm":goal.name,"expires":goal.expires,"source_ids":ids.duplicate(),"channel":"direct:"+resident},day,provider,["human",resident]):result.accepted+=1
			else:result.rejected+=1
			continue
		var weekly:bool=item.get("kind","")=="weekly"
		if weekly and (not request.get("weekly",false) or layer!="daily"):result.rejected+=1;continue
		var portrait:bool=item.get("kind","")=="portrait"
		if layer=="about_you" and not sources.all(func(e):return (e.layer=="facts" and e.params.get("human_quote",false)) or (portrait and e.layer=="about_you")):result.rejected+=1;continue
		if layer=="feelings" and not sources.all(func(e):return e.layer=="facts" and e.source=="game"):result.rejected+=1;continue
		var target_day:int=int(request.get("day",day))
		if layer=="daily":
			var days:Array=[]
			for e in sources:
				if e.layer=="facts" and e.day not in days:days.append(e.day)
			if days.size()==1 and int(days[0]) in request.get("rebuild_days",[]):target_day=int(days[0])
		if layer in ["letters","daily"]:
			if not request.has("day") or not sources.all(func(e):return ((e.day==target_day or (weekly and e.day>=maxi(1,target_day-6) and e.day<=target_day)) and e.layer=="facts") or e.layer=="about_you"):result.rejected+=1;continue
			if layer=="letters" and (text.length()<80 or text.length()>200):result.rejected+=1;continue
		if portrait and (not request.get("portrait",false) or layer!="about_you"):result.rejected+=1;continue
		if layer=="daily" and not weekly and not dirty_daily.has(resident+":"+world_id+":"+str(target_day)) and list_for(resident,"daily").any(func(e):return e.world_id==world_id and e.day==target_day and e.params.get("ai",false)):result.rejected+=1;continue
		var event_id:String=("weekly:"+str(target_day/7) if weekly else "portrait:"+str(int((day-1)/7)) if portrait else "letter:"+str(target_day) if layer=="letters" else "daily-ai:"+str(target_day)+":"+JSON.stringify(deleted).sha256_text() if layer=="daily" else "ai:"+layer+":"+JSON.stringify(ids).sha256_text())
		var params:Dictionary={"source_ids":ids.duplicate(),"channel":"direct:"+resident,"ai":true,"kind":"weekly" if weekly else "portrait" if portrait else "","provider":provider}
		if layer=="letters":
			var photos:Array=list_for(resident,"facts").filter(func(e):return e.world_id==world_id and e.day==target_day and not e.photo_id.is_empty())
			if not photos.is_empty():params["attachment"]=photos[0].photo_id
		if layer=="about_you" and not portrait:
			if list_for(resident,"about_you").any(func(e):return e.world_id==world_id and e.params.get("ai",false) and e.params.get("kind","")!="portrait" and e.params.get("source_ids",[])==ids):result.rejected+=1;continue
			var local_notes:Array=list_for(resident,"about_you").filter(func(e):return e.world_id==world_id and e.source=="local" and e.params.get("source_ids",[])==ids and not e.params.has("alias"))
			if not local_notes.is_empty():
				var merged:Dictionary=local_notes[0].duplicate(true);merged.text=text;merged.source=provider;merged.params=params
				if atomic(directory.path_join(merged.id+".entry.json"),merged):entries[merged.id]=merged;result.accepted+=1
				else:result.rejected+=1
				continue
		if add(resident,world_id,event_id,layer,text,params,day if portrait else target_day,provider,["human",resident]):
			result.accepted+=1
			if layer=="daily":
				dirty_daily.erase(resident+":"+world_id+":"+str(target_day));atomic(directory.path_join("dirty-daily.json"),dirty_daily)
				for old in list_for(resident,"daily"):
					if old.world_id==world_id and old.day==target_day and old.source=="local":retire_summary(old.id)
		else:result.rejected+=1
	return result
func ai_sources(resident:String,world_id:String,day:int=0,channel:String="")->Array:
	return list_for(resident).filter(func(e):return e.world_id==world_id and (channel!="group:all" or e.params.get("channel","")=="group:all" or (e.layer=="facts" and not e.params.get("human_quote",false))) and (e.layer=="about_you" or (e.layer=="facts" and (day==0 or e.day==day)))).slice(-24).map(func(e):return {"id":e.id,"event_id":e.event_id,"layer":e.layer,"text":render(e),"day":e.day,"human_quote":e.params.get("human_quote",false)})
func learn(resident:String,world_id:String,message_id:String,text:String,day:int)->bool:
	var regex:=RegEx.new();regex.compile(Text.source("memory.teach_pattern") )
	var found:=regex.search(text)
	if found==null:return false
	var alias:String=found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(3)
	var meaning:String=found.get_string(2) if not found.get_string(2).is_empty() else found.get_string(4)
	# This records a human-taught phrase; execution still goes through the original parser/UI.
	var quote:String=(resident+"|"+world_id+"|"+message_id+"|facts").sha256_text()
	return add(resident,world_id,"agreement:"+message_id,"about_you",text,{"alias":alias.strip_edges(),"meaning":meaning.strip_edges(),"source_ids":[quote],"human_quote":true,"channel":"direct:"+resident},day,"local",["human",resident])
func resolve(resident:String,text:String)->String:
	var notes:Array=list_for(resident,"about_you").slice(-100);notes.reverse()
	for e in notes:
		if e.params.get("alias","")==text:return str(e.params.meaning)
	return text

func photo_path(relative:String)->String:
	var regex:=RegEx.new();regex.compile("^photos/[0-9]+/[a-f0-9]{64}\\.png$")
	return directory.path_join(relative) if regex.search(relative)!=null else ""
func photo_html(relative:String)->String:
	var path:String=photo_path(relative)
	if path.is_empty() or not FileAccess.file_exists(path):return ""
	var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path)
	if bytes.size()>1048576:return ""
	return "<img width='320' height='200' alt='Photo' src='data:image/png;base64,"+Marshalls.raw_to_base64(bytes)+"'>"

func decide_goal(id:String,accept:bool)->bool:
	if not entries.has(id) or entries[id].params.get("goal_status","")!="offered":return false
	var e:Dictionary=entries[id].duplicate(true);e.params.goal_status="accepted" if accept else "declined"
	if not atomic(directory.path_join(id+".entry.json"),e):return false
	entries[id]=e;return true

func retire_summary(id:String)->bool:
	if not entries.has(id) or entries[id].layer!="daily" or entries[id].source!="local":return false
	var tombstones:Dictionary=deleted.duplicate();tombstones[id]=true
	if not atomic(directory.path_join("deleted.json"),tombstones):return false
	deleted=tombstones;entries.erase(id)
	return true

# Offered only after an exact bound, accepted AI reply. The player decides what
# matters. No model can create a quote by calling this through a game tool.
func offer_ai_quote(resident:String,world_id:String,turn:String,text:String,provider:String,day:int,channel:String)->void:
	if turn.is_empty() or provider.is_empty() or text.strip_edges().length()<8 or text.length()>1000:return
	latest_ai[resident]={"world":world_id,"turn":turn,"text":text,"provider":provider,"day":day,"channel":channel}
func keep_ai_quote(resident:String)->bool:
	if not latest_ai.has(resident):return false
	var q:Dictionary=latest_ai[resident]
	if not add(resident,q.world,"kept-ai:"+q.turn,"feelings",q.text,{"ai_quote":true,"provider":q.provider,"turn_key":q.turn,"channel":q.channel,"selected_by":"player"},q.day,q.provider,[resident,"human"]):return false
	latest_ai.erase(resident)
	var quotes:Array=list_for(resident).filter(func(e):return e.params.get("ai_quote",false))
	while quotes.size()>quote_limit:
		remove(quotes[0].id);quotes.pop_front()
	return true
func local_quotes(resident:String)->Array:
	# Daily/feelings generated by AI already passed exact real-source checks.
	return list_for(resident).filter(func(e):return (e.params.get("ai_quote",false) and e.params.get("selected_by")=="player" and not str(e.params.get("turn_key","")).is_empty()) or (e.params.get("ai",false) and e.layer=="feelings" and not e.params.get("source_ids",[]).is_empty() and e.params.source_ids.all(func(id):return entries.has(id) and entries[id].resident_id==resident))).slice(-quote_limit)
func quote_label(entry:Dictionary)->String:
	return ("AI 时期 · " if TranslationServer.get_locale().begins_with("zh") else "From our AI days · ")+str(entry.params.get("provider",entry.source))+" · "+render(entry)
