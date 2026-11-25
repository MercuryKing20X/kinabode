extends RefCounted

const Backup=preload("res://scripts/save_backup.gd")
const MARKER="island-v2.before-world.json"
const SIDECARS="before-world-files"
const EXTRA=["language.cfg","connection-overview.cfg","ui-scale.cfg"]

static func prepare(directory:String)->bool:
	var root:=DirAccess.open(directory)
	if root==null or not root.file_exists("island-v2.json"):return true
	if root.is_link(MARKER) or root.is_link(SIDECARS) or root.is_link("island-v2.json"):return false
	if root.file_exists(MARKER) and root.dir_exists(SIDECARS):return true
	var backup:=Backup.new()
	backup.directory=directory
	var names:=backup.source_names()
	for name in EXTRA:
		if root.file_exists(name) and not root.is_link(name):names.append(name)
	if not root.dir_exists(SIDECARS):
		var folder:=directory.path_join(SIDECARS)
		var scratch:=folder+"-"+str(Time.get_ticks_usec())+".tmp"
		if DirAccess.make_dir_recursive_absolute(scratch)!=OK:return false
		if OS.get_name()!="Windows" and FileAccess.set_unix_permissions(scratch,448)!=OK:return false
		for name in names:
			if name in ["island-v2.json","memories/signing.key"]:continue
			var target:=scratch.path_join(name)
			if DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK:return false
			if DirAccess.copy_absolute(directory.path_join(name),target)!=OK:return false
		if DirAccess.rename_absolute(scratch,folder)!=OK:return false
	if root.file_exists(MARKER):return true
	var target:=directory.path_join(MARKER)
	var temporary:=target+"-"+str(Time.get_ticks_usec())+".tmp"
	return DirAccess.copy_absolute(directory.path_join("island-v2.json"),temporary)==OK and DirAccess.rename_absolute(temporary,target)==OK
