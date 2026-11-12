extends SceneTree
const Cards=preload("res://scripts/persona_cards.gd")
func _initialize()->void:
	for text in ["~~~python\nprint(1)\n~~~","example.com/x","https://example.com","```hi```","作为 AI 模型","One. Two. Three. Four"]:assert(not Cards.safe_speech(text),text)
	for text in ["嗯……我在呢～","工作累了吗？过来坐一会儿吧，火还暖着。","Mm… the fire is warm."]:assert(Cards.safe_speech(text),text)
	var pool:=preload("res://scripts/connection_session_pool.gd").new();pool.directory=OS.get_environment("HABITAT_DATA_DIR");assert(pool.directory.contains("youqi-"));assert(pool.rows().size()==4);pool.free()
	print("PERSONA_GUARD 9 checks passed");quit()
