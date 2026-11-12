extends "res://scripts/main.gd"
## Explicit test seam: InputEventKey cannot manufacture a native OS preedit buffer.
## This fixture tests the host's submission barrier, not an actual IME provider.
var composing_fixture:=false
func _chat_is_composing()->bool:
	return composing_fixture or super._chat_is_composing()
