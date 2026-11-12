extends RefCounted
# Audit actual visible controls, without translating player/model data by text.
static func texts(node:Node)->Array:
	var result:Array=[]
	if node is CanvasItem and not node.is_visible_in_tree():return result
	if node is Window and not node.visible:return result
	if node is Label or node is Button or node is RichTextLabel:
		if not node.has_meta("user_authored_text"):result.append({"path":str(node.get_path()),"text":node.text})
	if node is AcceptDialog and not node.dialog_text.is_empty():result.append({"path":str(node.get_path())+":dialog_text","text":node.dialog_text})
	if node is Window and not node.title.is_empty():result.append({"path":str(node.get_path())+":title","text":node.title})
	if node is PopupMenu:
		for index in node.item_count:result.append({"path":str(node.get_path())+":"+str(index),"text":node.get_item_text(index)})
	for child in node.get_children():result.append_array(texts(child))
	return result
static func violations(node:Node,locale:String,allowed:Array=[])->Array:
	var failures:Array=[];var cjk:=RegEx.new();cjk.compile("[\\x{3400}-\\x{9fff}]")
	var key:=RegEx.new();key.compile("(?:ui|system|hud|panels|activities|storage|jieqi)\\.[a-z_]+(?:\\.[a-z_]+)*")
	# Reject English prose in Chinese, allowing authored short IDs and notation
	# only when the caller explicitly supplies the genuine user-data whitelist.
	var prose:=RegEx.new();prose.compile("[A-Za-z]{2,}(?:[ ,·]+[A-Za-z]{2,}){2,}")
	for entry in texts(node):
		if str(entry.text).is_empty() or str(entry.text) in allowed:continue
		if key.search(str(entry.text))!=null or (locale.begins_with("en") and cjk.search(str(entry.text))!=null) or (locale.begins_with("zh") and prose.search(str(entry.text))!=null):failures.append(entry)
	return failures
