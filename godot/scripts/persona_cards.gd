extends RefCounted
static func card(id:String,locale:String="",base:String="")->Dictionary:
	var lang:String="en" if (TranslationServer.get_locale() if locale.is_empty() else locale).begins_with("en") else "zh"
	var world:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/personas/world."+lang+".json"))
	var person:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/personas/"+id+"."+lang+".json"))
	var text:String="\n\n".join(world.sections+person.sections)
	if not base.is_empty():
		var overrides:=ConfigFile.new()
		if overrides.load(base.path_join("persona-overrides.cfg"))==OK:text=str(overrides.get_value(lang,id,text))
	return {"persona_id":id,"language":lang,"text":text}
static func safe_speech(text:String)->bool:
	var lower:=text.to_lower()
	for forbidden in ["```","~~~","http://","https://","www.",preload("res://scripts/localization.gd").source("content.connection.match.guard_spaced"),preload("res://scripts/localization.gd").source("content.connection.match.guard"),preload("res://scripts/localization.gd").source("content.connection.match.cannot"),"as an ai","as a language model"]:
		if forbidden in lower:return false
	var url:=RegEx.new();url.compile("[a-z0-9-]+\\.(com|org|net|io|cn|dev|ai)(/|\\b)")
	if url.search(lower)!=null:return false
	var regex:=RegEx.new();regex.compile("[。！？.!?]+")
	var matches:=regex.search_all(text)
	var sentences:=matches.size()
	if not text.strip_edges().is_empty() and (matches.is_empty() or matches[-1].get_end()<text.strip_edges().length()):sentences+=1
	return text.length()<=280 and sentences<=3
