extends RefCounted
## Shared translation loader; locale preferences belong to local cfg, never World.
static var loaded:=false
static var entries:Dictionary={}
static var content_keys:Dictionary={}
static var speech_keys:Dictionary={}
static var rendered_speech:Dictionary={}
static var speech_templates:Array=[]
class LocaleEvents extends RefCounted:
	signal changed
static var events:=LocaleEvents.new()
static func ensure()->void:
	if loaded:return
	loaded=true
	var zh:=Translation.new();zh.locale="zh_CN";var en:=Translation.new();en.locale="en"
	var directory:=DirAccess.open("res://content/i18n")
	if directory==null:return
	var files:=directory.get_files();files.sort()
	for name in files:
		if not name.ends_with(".csv"):continue
		var file:=FileAccess.open("res://content/i18n/"+name,FileAccess.READ)
		var header:=file.get_csv_line()
		while not file.eof_reached():
			var row:=file.get_csv_line()
			if row.size()!=header.size() or row.size()!=3:continue
			zh.add_message(row[0],row[1]);en.add_message(row[0],row[2]);entries[row[0]]={"zh":row[1],"en":row[2]}
			if row[0].begins_with("content."):
				content_keys[row[1]]=row[0];content_keys[row[2]]=row[0]
				if "{" in row[1]:_add_speech_template(row[0],row[1])
				if row[0].begins_with("content.speech."):
					if not speech_keys.has(row[1]):speech_keys[row[1]]=[]
					speech_keys[row[1]].append(row[0])
	TranslationServer.add_translation(zh);TranslationServer.add_translation(en)
	TranslationServer.set_locale("zh_CN")
static func text(key:String)->String:
	ensure();return TranslationServer.translate(key)
static func source(key:String)->String:
	ensure();return str(entries.get(key,{}).get("zh",key))
static func content(value:String)->String:
	ensure();return text(str(content_keys[value])) if content_keys.has(value) else value
static func receipt(value:String)->String:
	ensure()
	for key in entries:
		if value in [str(entries[key].zh),str(entries[key].en)]:return text(str(key))
	return value
static func revision()->String:
	ensure();return TranslationServer.get_locale()
static func speech(world:RefCounted,id:String,value:String)->String:
	ensure()
	if value.begins_with("♨ "):return "♨ "+speech(world,id,value.trim_prefix("♨ "))
	if world.gomoku!=null and world.gomoku.companion!=null:
		for profile in world.gomoku.companion.config.traits.values():
			var prefix:String=str(profile.get("close_prefix",""))
			if not prefix.is_empty() and value.begins_with(prefix):return content(prefix)+speech(world,id,value.trim_prefix(prefix))
	var trait_id:String=world.intelligence.tag(id)
	var binding:Dictionary=rendered_speech.get(id+":"+value,{})
	if binding.is_empty() and not speech_keys.has(value) and revision().begins_with("en"):
		for template in speech_templates:
			if str(template.key).begins_with("content.speech.") and not (str(template.key).contains("."+trait_id+"-") or str(template.key).contains("-"+trait_id+"-")):continue
			var matched:RegExMatch=template.regex.search(value)
			if matched==null:continue
			var params:Dictionary={}
			for i in template.params.size():params[template.params[i]]=matched.get_string(i+1)
			binding={"key":template.key,"params":params};rendered_speech[id+":"+value]=binding
			if rendered_speech.size()>512:rendered_speech.erase(rendered_speech.keys()[0])
			break
	if not binding.is_empty():
		var translated:String=text(binding.key)
		for name in binding.params:
			var argument:String=str(binding.params[name])
			if name in ["catcher","resident","actor","name"]:
				for actor_id in world.actors:
					if world.actors[actor_id].name==argument:argument=resident(world,actor_id);break
			elif name=="address":
				var preferences:ConfigFile=world.relationships.preference_file
				var custom:bool=preferences!=null and preferences.has_section_key("resident:"+id,"human_address")
				if not custom and argument==str(world.relationships.config.rewards.default_address):argument=text("resident.you") if argument==source("resident.you") else content(argument)
			else:argument=content(argument)
			translated=translated.replace("{"+str(name)+"}",argument)
		return translated
	for key in speech_keys.get(value,[]):
		if str(key).contains("."+trait_id+"-") or str(key).contains("-"+trait_id+"-"):return text(key)
	return content(value)
static func _add_speech_template(key:String,value:String)->void:
	var tokens:=RegEx.new();tokens.compile("\\{([A-Za-z_][A-Za-z_0-9]*)\\}")
	var params:Array=[];var pattern:="^";var cursor:=0
	for token in tokens.search_all(value):
		pattern+=_regex_literal(value.substr(cursor,token.get_start()-cursor))+"(.+?)";params.append(token.get_string(1));cursor=token.get_end()
	pattern+=_regex_literal(value.substr(cursor))+"$"
	var regex:=RegEx.new()
	if regex.compile(pattern)==OK:speech_templates.append({"key":key,"regex":regex,"params":params})
static func _regex_literal(value:String)->String:
	var result:=""
	for char in value:
		if char in ".^$*+?()[]\\|{}":result+="\\"
		result+=char
	return result
static func remember_speech(id:String,rendered:String,template:String,params:Dictionary,pool_id:String)->void:
	ensure()
	for key in speech_keys.get(template,[]):
		if str(key).begins_with("content.speech."+pool_id+"."):
			rendered_speech[id+":"+rendered]={"key":key,"params":params.duplicate(true)}
			if rendered_speech.size()>512:rendered_speech.erase(rendered_speech.keys()[0])
			return
static func resident(world:RefCounted,id:String)->String:
	ensure()
	if not world.actors.has(id):return text("resident.unknown")
	var actor:Dictionary=world.actors[id];var name:String=str(actor.name)
	if actor.get("custom_name",false):return name
	var key:String={"human":"resident.you","codex":"resident.snow","companion-2":"resident.skye","npc.mira":"resident.clem","npc.nora":"resident.raven"}.get(id,"")
	if id=="npc.mira" and name==source("resident.mira"):return text("resident.mira")
	if id=="npc.nora" and name==source("resident.nora"):return text("resident.nora")
	if not key.is_empty() and name==source(key):return text(key)
	return name
static func configure(directory:String)->String:
	ensure()
	var cfg:=ConfigFile.new();cfg.load(directory.path_join("language.cfg"))
	var locale:String="en" if cfg.get_value("ui","language","zh")=="en" else "zh"
	TranslationServer.set_locale("en" if locale=="en" else "zh_CN")
	return locale
static func select(directory:String,locale:String)->void:
	ensure();TranslationServer.set_locale("en" if locale=="en" else "zh_CN")
	var cfg:=ConfigFile.new();cfg.set_value("ui","language",locale);cfg.save(directory.path_join("language.cfg"))
	events.changed.emit()
