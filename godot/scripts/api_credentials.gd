extends RefCounted
## Local configuration only. Never place credentials/endpoints in cards, saves, errors or logs.
static func read_settings(base:String)->ConfigFile:
	var settings:=ConfigFile.new()
	settings.load(base.path_join("connection-mode.cfg"))
	return settings
static func key(base:String)->String:
	var value:=OS.get_environment("HABITAT_OPENAI_KEY").strip_edges()
	if not value.is_empty():return value
	var local:=ConfigFile.new()
	local.load(base.path_join("api-secret.cfg"))
	return str(local.get_value("api","key","")).strip_edges()
static func save_key(base:String,value:String)->bool:
	var local:=ConfigFile.new()
	local.set_value("api","key",value.strip_edges())
	var path:=base.path_join("api-secret.cfg")
	if local.save(path)!=OK:return false
	if OS.get_name()!="Windows":FileAccess.set_unix_permissions(path,384)
	return true
static func endpoint(value:String)->String:
	var base:=value.strip_edges().trim_suffix("/")
	if base.ends_with("/chat/completions"):base=base.trim_suffix("/chat/completions")
	if "@" in base or "?" in base or "#" in base or "\n" in base or "\r" in base:return ""
	var regex:=RegEx.new()
	regex.compile("^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^ ]*)?$")
	if regex.search(base)==null:
		regex.compile("^http://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]+)?(/[^ ]*)?$")
		if regex.search(base)==null:return ""
	var authority:=base.split("://")[1]
	if "/" not in authority:base+="/v1"
	return base
