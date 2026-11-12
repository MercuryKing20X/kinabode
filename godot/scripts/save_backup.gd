extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## docs/SAVE_BACKUP.md. Copies on-disk sources only; never saves or restores a world.
const DEFAULTS={"version":1,"recent_count":10,"daily_days":7,"max_total_bytes":536870912}
const CREATOR="youxi-save-backup"
const ROOT_FILES=["island-v2.json","local-life.cfg","intelligence-preferences.cfg","appearance-preferences.cfg","resident-intelligence-ui.cfg","audio.cfg","connection-mode.cfg","conversation-binding.cfg"]
const MAX_SOURCE_BYTES=256*1024*1024
var config:Dictionary=DEFAULTS.duplicate(true)
var directory:=""
var active:=false
var last_day:=0
var last_at:=""
var last_error:=""

func setup(data_directory:String,options:Dictionary={}) -> bool:
	var candidate:Dictionary=DEFAULTS.duplicate(true)
	var path:="res://content/save-backup.json"
	if FileAccess.file_exists(path):
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not valid_config(value):last_error=LocalText.text("system.save_backup.the_backup_settings_are_invalid");return false
		candidate=value
	candidate.merge(options,true)
	if not valid_config(candidate):last_error=LocalText.text("system.save_backup.the_backup_settings_are_invalid");return false
	config=candidate;directory=data_directory;active=false;last_day=0;last_at="";last_error=""
	var previous:Array=archives()
	if not previous.is_empty():last_at=str(previous[-1].get("local_time",""))
	return true

static func valid_config(value:Variant)->bool:
	if not value is Dictionary or value.size()!=DEFAULTS.size() or not value.has_all(DEFAULTS.keys()) or value.version!=1:return false
	for key in DEFAULTS:
		if not (value[key] is int or value[key] is float) or not is_finite(value[key]) or value[key]!=floor(value[key]):return false
	return value.recent_count>=1 and value.recent_count<=100 and value.daily_days>=1 and value.daily_days<=30 and value.max_total_bytes>=1048576 and value.max_total_bytes<=2147483648

func folder()->String:return directory.path_join("backups") if not directory.is_empty() else ""
func summary()->String:
	var message:String=LocalText.text("ui.backup.latest") % (last_at if not last_at.is_empty() else LocalText.text("ui.backup.none"))
	if not last_error.is_empty():message+="\n"+LocalText.text("ui.backup.failed") % last_error
	return message

func startup(loaded_ok:bool,was_loaded:bool,day:int)->Dictionary:
	active=loaded_ok and not directory.is_empty();last_day=day
	if not active or not was_loaded:return {"ok":true,"skipped":true}
	return backup()

func tick(day:int)->Dictionary:
	if not active or day<=last_day:return {"ok":true,"skipped":true}
	# One observed transition, without offline replay or per-frame failure retries.
	last_day=day
	return backup()

func source_names()->Array:
	var names:Array=[]
	if directory.is_empty():return names
	var root:DirAccess=DirAccess.open(directory)
	if root==null:return names
	for filename in ROOT_FILES:
		if root.file_exists(filename) and not root.is_link(filename):names.append(filename)
	if root.dir_exists("characters") and not root.is_link("characters"):
		var art:DirAccess=DirAccess.open(directory.path_join("characters"))
		if art!=null:
			for filename in art.get_files():
				if filename.ends_with(".json") and not art.is_link(filename):names.append("characters/"+filename)
	if root.dir_exists("memories") and not root.is_link("memories"):
		var memories:DirAccess=DirAccess.open(directory.path_join("memories"))
		if memories!=null:
			for filename in memories.get_files():
				if not memories.is_link(filename) and (filename.ends_with(".json") or filename=="signing.key"):names.append("memories/"+filename)
	if root.dir_exists("life") and not root.is_link("life"):
		var life_dir:DirAccess=DirAccess.open(directory.path_join("life"))
		if life_dir!=null:
			for filename in life_dir.get_files():
				if _life_name("life/"+filename) and not life_dir.is_link(filename):names.append("life/"+filename)
	var photos:String=directory.path_join("memories/photos")
	if DirAccess.dir_exists_absolute(photos):
		for volume in DirAccess.get_directories_at(photos):
			var parent:=DirAccess.open(photos)
			if not volume.is_valid_int() or parent.is_link(volume):continue
			var folder:=DirAccess.open(photos.path_join(volume))
			for filename in folder.get_files():
				if filename.ends_with(".png") and filename.get_basename().length()==64 and filename.get_basename().is_valid_hex_number(false) and not folder.is_link(filename):names.append("memories/photos/"+volume+"/"+filename)
	names.sort();return names

func snapshot()->Dictionary:
	var names:Array=source_names()
	if not names.has("island-v2.json"):return {"ok":false,"error":LocalText.text("system.save_backup.no_saved_world_was_found_to_back_up")}
	var files:Dictionary={};var payloads:Dictionary={};var bytes:=0
	for name in names:
		var file:FileAccess=FileAccess.open(directory.path_join(name),FileAccess.READ)
		if file==null:return {"ok":false,"error":LocalText.text("system.save_backup.cannot_read")+str(name)}
		var length:int=file.get_length();bytes+=length
		if bytes>MAX_SOURCE_BYTES:file.close();return {"ok":false,"error":LocalText.text("system.save_backup.backup_sources_exceed_the_safe_read_limit")}
		var data:PackedByteArray=file.get_buffer(length);file.close()
		if data.size()!=length:return {"ok":false,"error":LocalText.text("system.save_backup.incomplete_read")+str(name)}
		payloads[name]=data;files[name]={"bytes":length,"sha256":digest(data)}
	return {"ok":true,"files":files,"payloads":payloads,"content_hash":digest(JSON.stringify(files).to_utf8_buffer())}

static func digest(data:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(data);return context.finish().hex_encode()

func backup()->Dictionary:
	if directory.is_empty():return fail(LocalText.text("system.save_backup.there_is_no_data_directory"))
	var sources:Dictionary=snapshot()
	if not sources.ok:return fail(str(sources.error))
	var previous:Array=archives()
	if not previous.is_empty() and previous[-1].content_hash==sources.content_hash and verify_archive(previous[-1].path,previous[-1]):
		last_at=str(previous[-1].local_time);last_error="";return {"ok":true,"skipped":true,"content_hash":sources.content_hash}
	var base:DirAccess=DirAccess.open(directory)
	if base==null or (base.dir_exists("backups") and base.is_link("backups")):return fail(LocalText.text("system.save_backup.the_backup_folder_is_unavailable"))
	if DirAccess.make_dir_recursive_absolute(folder())!=OK:return fail(LocalText.text("system.save_backup.cannot_create_the_backup_folder_check_disk_space_and"))
	var created:float=Time.get_unix_time_from_system()
	var local_time:String=Time.get_datetime_string_from_system(false,true)
	var utc:String=Time.get_datetime_string_from_unix_time(int(created)).replace("-","").replace(":","")
	var name:String="youxi-"+utc+"Z-"+str(Time.get_ticks_usec())+"-"+str(sources.content_hash).left(12)+".zip"
	var target:String=folder().path_join(name);var temporary:String=target+".tmp"
	var writer:=ZIPPacker.new()
	if writer.open(temporary)!=OK:return fail(LocalText.text("system.save_backup.cannot_write_the_backup_check_disk_space_and_permissions"))
	var metadata:Dictionary={"creator":CREATOR,"version":1,"created_at":created,"local_time":local_time,"local_date":local_time.left(10),"content_hash":sources.content_hash,"files":sources.files}
	var success:bool=zip_entry(writer,"backup-manifest.json",JSON.stringify(metadata).to_utf8_buffer())
	for filename in sources.payloads:
		if not success:break
		success=zip_entry(writer,filename,sources.payloads[filename])
	var close_error:int=writer.close()
	if not success or close_error!=OK:
		DirAccess.remove_absolute(temporary);return fail(LocalText.text("system.save_backup.writing_the_backup_archive_failed"))
	if file_size(temporary)>int(config.max_total_bytes):
		DirAccess.remove_absolute(temporary);return fail(LocalText.text("system.save_backup.one_backup_exceeds_the_total_size_limit"))
	# Rename only after close and readback verification; do not touch originals.
	var verify:Dictionary=archive_metadata(temporary)
	if verify.is_empty():DirAccess.remove_absolute(temporary);return fail(LocalText.text("system.save_backup.backup_metadata_validation_failed"))
	if not verify_archive(temporary,metadata):DirAccess.remove_absolute(temporary);return fail(LocalText.text("system.save_backup.backup_content_validation_failed"))
	if DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary);return fail(LocalText.text("system.save_backup.finalizing_the_backup_failed"))
	last_at=local_time;last_error=""
	var pruned:Dictionary=prune()
	if not pruned.ok:last_error=LocalText.text("system.save_backup.old_backups_could_not_be_cleaned_up")
	return {"ok":true,"skipped":false,"path":target,"content_hash":sources.content_hash,"pruned":pruned.get("removed",[])}

static func zip_entry(writer:ZIPPacker,name:String,data:PackedByteArray)->bool:
	if writer.start_file(name)!=OK:return false
	var result:int=writer.write_file(data);var closed:int=writer.close_file()
	return result==OK and closed==OK

func fail(message:String)->Dictionary:
	last_error=message;return {"ok":false,"error":message}

static func file_size(path:String)->int:
	var file:FileAccess=FileAccess.open(path,FileAccess.READ)
	if file==null:return 0
	var size:int=file.get_length();file.close();return size

static func archive_metadata(path:String)->Dictionary:
	var reader:=ZIPReader.new()
	if reader.open(path)!=OK:return {}
	if not reader.file_exists("backup-manifest.json"):reader.close();return {}
	var raw:PackedByteArray=reader.read_file("backup-manifest.json");reader.close()
	if raw.size()>1048576:return {}
	var value:Variant=JSON.parse_string(raw.get_string_from_utf8())
	if not value is Dictionary or value.get("creator")!=CREATOR or value.get("version")!=1 or not value.get("files") is Dictionary or not value.files.has("island-v2.json") or not value.get("content_hash") is String or value.content_hash.length()!=64 or not value.content_hash.is_valid_hex_number(false):return {}
	if not (value.get("created_at") is int or value.get("created_at") is float) or not is_finite(value.created_at) or value.created_at<0 or not value.get("local_time") is String or not value.get("local_date") is String or value.local_date.length()!=10:return {}
	if value.files.size()>104096 or value.files.keys().filter(func(name):return not str(name).begins_with("memories/")).size()>4096:return {}
	var total:=0
	for name in value.files:
		if not name is String or not (name in ROOT_FILES or (name.get_base_dir()=="characters" and name.ends_with(".json")) or (name.get_base_dir()=="memories" and (name.ends_with(".json") or name.get_file()=="signing.key")) or _memory_photo_name(name) or _life_name(name)):return {}
		var entry:Variant=value.files[name]
		if not entry is Dictionary or entry.size()!=2 or not (entry.get("bytes") is int or entry.get("bytes") is float) or not is_finite(entry.bytes) or entry.bytes<0 or entry.bytes!=floor(entry.bytes) or not entry.get("sha256") is String or entry.sha256.length()!=64 or not entry.sha256.is_valid_hex_number(false):return {}
		total+=int(entry.bytes)
		if total>MAX_SOURCE_BYTES:return {}
	return value

static func verify_archive(path:String,metadata:Dictionary)->bool:
	var reader:=ZIPReader.new()
	if reader.open(path)!=OK:return false
	var names:Array=Array(reader.get_files()).filter(func(name):return not name.ends_with("/"))
	var valid:bool=names.size()==metadata.files.size()+1
	for name in metadata.files:
		var data:PackedByteArray=reader.read_file(name)
		if data.size()!=int(metadata.files[name].bytes) or digest(data)!=metadata.files[name].sha256:valid=false;break
	reader.close();return valid

func archives()->Array:
	var result:Array=[]
	if directory.is_empty():return result
	var base:DirAccess=DirAccess.open(directory)
	if base==null or base.is_link("backups"):return result
	var dir:DirAccess=DirAccess.open(folder())
	if dir==null:return result
	for name in dir.get_files():
		if not name.begins_with("youxi-") or not name.ends_with(".zip") or dir.is_link(name):continue
		var path:String=folder().path_join(name);var metadata:Dictionary=archive_metadata(path)
		if metadata.is_empty():continue
		metadata["path"]=path;metadata["bytes"]=file_size(path);result.append(metadata)
	result.sort_custom(func(a,b):return a.created_at<b.created_at if a.created_at!=b.created_at else a.path<b.path)
	return result

func prune()->Dictionary:
	var records:Array=archives();var keep:Dictionary={};var dates:Dictionary={};var total:=0;var removed:Array=[]
	var today:float=Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system())
	for index in range(records.size()-1,-1,-1):
		var record:Dictionary=records[index];total+=int(record.bytes)
		var age_days:float=(today-Time.get_unix_time_from_datetime_string(record.local_date))/86400.0
		if index>=records.size()-int(config.recent_count):keep[record.path]=true
		if age_days>=0 and age_days<float(config.daily_days) and not dates.has(record.local_date):keep[record.path]=true;dates[record.local_date]=true
	var failed:=false
	for record in records:
		if keep.has(record.path) and total<=int(config.max_total_bytes):continue
		if DirAccess.remove_absolute(record.path)==OK:total-=int(record.bytes);removed.append(record.path)
		else:failed=true
	return {"ok":not failed,"removed":removed,"remaining_bytes":total}

static func _memory_photo_name(name:String)->bool:
	var parts:PackedStringArray=name.split("/")
	return parts.size()==4 and parts[0]=="memories" and parts[1]=="photos" and parts[2].is_valid_int() and parts[3].ends_with(".png") and parts[3].get_basename().length()==64 and parts[3].get_basename().is_valid_hex_number(false)

static func _life_name(name:String)->bool:
	var leaf:String=name.get_file()
	return name.get_base_dir()=="life" and leaf.ends_with(".life.json") and leaf.trim_suffix(".life.json").length()==64 and leaf.trim_suffix(".life.json").is_valid_hex_number(false)
