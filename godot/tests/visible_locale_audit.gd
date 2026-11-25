extends RefCounted
const Glyphs=preload("res://tests/ui_glyph_audit.gd")
# Audit actual visible controls, without translating player/model data by text.
static func texts(node:Node)->Array:
	var result:Array=[]
	if node is CanvasItem and not node.is_visible_in_tree():return result
	if node is Window and not node.visible:return result
	if node is Label or node is Button or node is RichTextLabel:
		result.append({"path":str(node.get_path()),"text":node.get_parsed_text() if node is RichTextLabel else node.text,"user_authored":node.has_meta("user_authored_text")})
	if (node is LineEdit or node is TextEdit) and node.text.is_empty() and not node.placeholder_text.is_empty():
		result.append({"path":str(node.get_path())+":placeholder","text":node.placeholder_text})
	if node is AcceptDialog and not node.dialog_text.is_empty():result.append({"path":str(node.get_path())+":dialog_text","text":node.dialog_text})
	if node is Window and not node.title.is_empty():result.append({"path":str(node.get_path())+":title","text":node.title})
	if node is PopupMenu:
		for index in node.item_count:result.append({"path":str(node.get_path())+":"+str(index),"text":node.get_item_text(index)})
	for child in node.get_children():result.append_array(texts(child))
	return result
static func violations(node:Node,locale:String,allowed:Array=[])->Array:
	var failures:Array=[];var cjk:=RegEx.new();cjk.compile("[\\x{3400}-\\x{9fff}]")
	# Reject English prose in Chinese, allowing authored short IDs and notation
	# only when the caller explicitly supplies the genuine user-data whitelist.
	var prose:=RegEx.new();prose.compile("[A-Za-z]{2,}(?:[ ,·]+[A-Za-z]{2,}){2,}")
	for entry in texts(node):
		if str(entry.text).is_empty():continue
		var absent:=Glyphs.missing(str(entry.text))
		if not absent.is_empty():failures.append({"path":entry.path,"text":entry.text,"missing":absent})
		if entry.get("user_authored",false) or str(entry.text) in allowed:continue
		if raw_key(str(entry.text)) or (locale.begins_with("en") and cjk.search(str(entry.text))!=null) or (locale.begins_with("zh") and prose.search(str(entry.text))!=null):failures.append(entry)
	return failures

static var key_pattern:RegEx
static func raw_key(value:String)->bool:
	if key_pattern==null:
		key_pattern=RegEx.new()
		key_pattern.compile("(?<![A-Za-z0-9_./:@-])[A-Za-z_][A-Za-z0-9_-]*\\.(?:[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+)+|[A-Za-z0-9-]+_[A-Za-z0-9_-]+)(?![A-Za-z0-9_/@-])")
	return key_pattern.search(value)!=null
