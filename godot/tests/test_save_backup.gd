extends SceneTree
const Backup=preload("res://scripts/save_backup.gd")
const Save=preload("res://scripts/save_store.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func write(path:String,bytes:PackedByteArray)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir());var file:=FileAccess.open(path,FileAccess.WRITE);assert(file!=null);file.store_buffer(bytes);file.close()
func hashes(backup:RefCounted)->Dictionary:
	var result:Dictionary={}
	for name in backup.source_names():result[name]=FileAccess.get_sha256(backup.directory.path_join(name))
	return result
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var helper:=Helper.new();var dir:String=temp.path_join("first");var world:RefCounted=helper.fresh(dir)
	check(Save.save_world(world,dir),"fixture is a real valid world save")
	write(dir.path_join("characters/white-haired-girl.json"),JSON.stringify(world.library.artworks["white-haired-girl"]).to_utf8_buffer())
	write(dir.path_join("local-life.cfg"),"[life]\nenabled=true\n".to_utf8_buffer())
	write(dir.path_join("runtime/secret.txt"),"never include runtime".to_utf8_buffer())
	var b:=Backup.new();check(b.setup(dir),"default backup config accepted")
	var original:Dictionary=hashes(b);var result:Dictionary=b.startup(true,true,world.days.day())
	if not result.ok:helper.free();quit(1);return
	check(result.ok and not result.skipped and b.archives().size()==1,"successful loaded startup makes first archive")
	check(hashes(b)==original,"backup leaves every source byte unchanged")
	var reader:=ZIPReader.new();check(reader.open(result.path)==OK,"archive decompresses")
	check(not reader.file_exists("runtime/secret.txt") and Array(reader.get_files()).filter(func(n):return not n.ends_with("/")).size()==original.size()+1,"only explicit data and manifest included")
	for name in original:
		var restored:PackedByteArray=reader.read_file(name)
		check(Backup.digest(restored)==original[name],"exact readback "+name)
		write(temp.path_join("roundtrip").path_join(name),restored)
	reader.close()
	check(Save.load_world(helper.fresh(temp.path_join("load-world")),temp.path_join("roundtrip")).get("loaded",false),"decompressed original save loads through real save validator")
	check(b.backup().get("skipped",false) and b.archives().size()==1,"equal content hash does not duplicate")
	check(b.tick(world.days.day()).get("skipped",false),"same game day never repeats backup")
	write(dir.path_join("audio.cfg"),"[audio]\nenabled=false\n".to_utf8_buffer())
	check(not b.tick(world.days.day()+1).get("skipped",true) and b.archives().size()==2,"real observed next game day includes changed preferences")
	check(b.tick(world.days.day()+8).get("skipped",false),"skipped game days do not replay identical archives")
	var restart:=Backup.new();restart.setup(dir)
	check(not restart.last_at.is_empty() and restart.startup(true,true,world.days.day()).get("skipped",false),"restart discovers latest archive and deduplicates")
	var failure:=Backup.new();failure.setup(dir)
	check(failure.startup(false,true,1).get("skipped",false) and failure.tick(2).get("skipped",false),"failed source load never enables backups")
	var fresh:=Backup.new();fresh.setup(dir)
	check(fresh.startup(true,false,1).get("skipped",false),"new world has no synthetic startup save")
	for index in range(13):
		write(dir.path_join("audio.cfg"),("generation="+str(index)).to_utf8_buffer());check(b.backup().ok,"rotation fixture archive "+str(index))
	check(b.archives().size()==10,"same calendar day retains exactly newest ten")
	# Protect unrelated files in backups even if pruning runs.
	write(b.folder().path_join("user-file.zip"),"unrelated bytes".to_utf8_buffer());b.prune()
	check(FileAccess.get_file_as_string(b.folder().path_join("user-file.zip"))=="unrelated bytes","rotation never deletes unrelated user files")
	# Different wall days are fixture archive metadata, never a changed game clock.
	var seed:Dictionary=b.archives()[-1];var source_reader:=ZIPReader.new();source_reader.open(seed.path)
	var payloads:Dictionary={}
	for filename in source_reader.get_files():
		if not filename.ends_with("/"):payloads[filename]=source_reader.read_file(filename)
	source_reader.close()
	var today:int=Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system())
	for days_back in range(1,9):
		var metadata:Dictionary=Backup.archive_metadata(seed.path);metadata.created_at=Time.get_unix_time_from_system()-days_back*86400;metadata.local_date=Time.get_datetime_string_from_unix_time(today-days_back*86400).left(10)
		var writer:=ZIPPacker.new();writer.open(b.folder().path_join("youxi-fixture-day-"+str(days_back)+".zip"))
		for filename in payloads:Backup.zip_entry(writer,filename,JSON.stringify(metadata).to_utf8_buffer() if filename=="backup-manifest.json" else payloads[filename])
		writer.close()
	b.prune();check(b.archives().size()==16,"recent ten plus previous six calendar-day exemplars; eighth/seventh old discarded")
	var count_before:int=b.archives().size();var before_failure:Dictionary=hashes(b)
	var bad_dir:String=temp.path_join("disk-failure");write(bad_dir.path_join("island-v2.json"),FileAccess.get_file_as_bytes(dir.path_join("island-v2.json")));write(bad_dir.path_join("backups"),"blocks directory".to_utf8_buffer())
	var bad:=Backup.new();bad.setup(bad_dir)
	check(not bad.startup(true,true,1).ok and not bad.last_error.is_empty(),"disk/directory failure returns a nonfatal status")
	check(FileAccess.get_sha256(bad_dir.path_join("island-v2.json"))==original["island-v2.json"] and b.archives().size()==count_before and hashes(b)==before_failure,"failure changes no source or unrelated backups")
	check(bad.tick(1).get("skipped",false),"write failure does not retry each frame")
	var invalid:Dictionary=Backup.DEFAULTS.duplicate(true);invalid.recent_count=0;check(not Backup.valid_config(invalid),"invalid count rejected")
	invalid=Backup.DEFAULTS.duplicate(true);invalid.extra=1;check(not Backup.valid_config(invalid),"unknown config field rejected")
	invalid=Backup.DEFAULTS.duplicate(true);invalid.max_total_bytes=0;check(not Backup.valid_config(invalid),"invalid byte cap rejected")
	# 1 MiB cap fixture: incompressible existing content, no gameplay resource changes.
	var cap_dir:String=temp.path_join("byte-cap");write(cap_dir.path_join("island-v2.json"),"{\"size_rotation_fixture\":true}".to_utf8_buffer())
	var cap:=Backup.new();check(cap.setup(cap_dir,{"max_total_bytes":1048576}),"supported byte cap accepted")
	var rng:=RandomNumberGenerator.new();rng.seed=1031;var noise:=PackedByteArray();noise.resize(800000)
	for index in range(noise.size()):noise[index]=rng.randi()%256
	for index in range(3):noise[index]=index;write(cap_dir.path_join("local-life.cfg"),noise);check(cap.backup().ok,"byte cap fixture successful backup")
	var archives:Array=cap.archives();check(archives.size()==1 and archives[0].bytes<=1048576,"total size cap prunes oldest even within recent-count preference")
	check(Array(DirAccess.get_files_at(cap.folder())).filter(func(n):return n.ends_with(".tmp")).is_empty(),"no successful temporary archive remains")
	helper.free();print("Save backup: ",checks," checks; failed=",failed);quit(1 if failed else 0)
