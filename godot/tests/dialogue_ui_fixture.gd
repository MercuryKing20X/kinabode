extends RefCounted
## Dialogue tests explicitly enter Talk. New windows intentionally open Commands.
static func open(game:Node,target:String="")->void:
	if target.is_empty():target=game.Channels.ALL if game.group_chat else game.chat_actor
	game.chat.show()
	if game.command_page!=null:
		game.command_page.selected=game.command_page.actors() if target==game.Channels.ALL else [target]
		game.command_page.show_mode(false)
	game._select_chat(target)
static func send(game:Node,text:String)->void:
	open(game)
	game._send(text)
