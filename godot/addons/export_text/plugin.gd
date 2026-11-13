@tool
extends EditorPlugin
class SourceTextExport extends EditorExportPlugin:
	func _get_name()->String:return "KinabodeSourceText"
	func _export_begin(_features:PackedStringArray,_debug:bool,_path:String,_flags:int)->void:
		var directory:=DirAccess.open("res://content/i18n")
		for name in directory.get_files():
			if name.ends_with(".csv"):
				var path:="res://content/i18n/"+name
				add_file(path,FileAccess.get_file_as_bytes(path),false)
		_add_audio("res://content/audio")
	func _add_audio(folder:String)->void:
		var directory:=DirAccess.open(folder)
		for name in directory.get_files():
			if name.get_extension() in ["wav","ogg"]:
				var path:=folder.path_join(name)
				add_file(path,FileAccess.get_file_as_bytes(path),false)
		for name in directory.get_directories():_add_audio(folder.path_join(name))
var exporter:SourceTextExport
func _enter_tree()->void:
	exporter=SourceTextExport.new();add_export_plugin(exporter)
func _exit_tree()->void:
	remove_export_plugin(exporter)
