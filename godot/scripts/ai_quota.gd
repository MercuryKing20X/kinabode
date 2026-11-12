extends RefCounted
## Local daily allowance follows the stable resident across world files.
## Existing per-world ledgers remain authoritative and are never rewritten here.
static func usage(directory:String,id:String)->Dictionary:
	var result:Dictionary={"tokens":0,"reserved":0,"unknown_turns":0,"input_tokens":0,"output_tokens":0,"invalid":false}
	var cfg:=ConfigFile.new()
	if cfg.load(directory.path_join("resident-intelligence-ui.cfg"))!=OK:
		if FileAccess.file_exists(directory.path_join("resident-intelligence-ui.cfg")):result.invalid=true;result.unknown_turns=1
		return result
	var today:int=int(floor((Time.get_unix_time_from_system()+Time.get_time_zone_from_system().bias*60)/86400.0))
	for section in cfg.get_sections():
		if not section.ends_with("/"+id):continue
		var account:Variant=cfg.get_value(section,"autonomy_accounting",{})
		if not account is Dictionary:
			result.invalid=true;result.unknown_turns+=1;continue
		if account.is_empty() or account.get("day",-1)!=today:continue
		var valid:=true
		for field in ["tokens","reserved","unknown_turns","input_tokens","output_tokens"]:
			var n:Variant=account.get(field)
			if not (n is int or n is float) or not is_finite(n) or n<0 or n!=floor(n):valid=false;break
		if not valid:
			result.invalid=true;result.unknown_turns+=1;continue
		for field in ["tokens","reserved","unknown_turns","input_tokens","output_tokens"]:result[field]+=int(account[field])
	return result
static func reached(directory:String,id:String,maximum:int)->bool:
	if maximum<=0:return false
	var used:Dictionary=usage(directory,id)
	return used.invalid or int(used.tokens)+int(used.reserved)>=maximum
