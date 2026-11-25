extends AcceptDialog

const Text=preload("res://scripts/world_creations.gd")
var game:Node
var days:ItemList
var error:Label
var undo:Button

func setup(host:Node)->void:
	game=host
	dialog_hide_on_ok=false
	var stack:=VBoxContainer.new()
	add_child(stack)
	days=ItemList.new()
	days.fixed_icon_size=Vector2i(144,90)
	days.custom_minimum_size=Vector2(410,285)
	stack.add_child(days)
	error=Label.new()
	stack.add_child(error)
	undo=Button.new()
	stack.add_child(undo)
	undo.pressed.connect(func():apply("undo"))
	days.item_selected.connect(func(_i):get_ok_button().disabled=false)
	confirmed.connect(func():
		var selected:=days.get_selected_items()
		if not selected.is_empty():apply(days.get_item_metadata(selected[0])))
	refresh_locale()
	preload("res://scripts/localization.gd").events.changed.connect(refresh_locale)

func refresh_locale()->void:
	title=Text.phrase("回到昨天","Return to yesterday")
	ok_button_text=Text.phrase("恢复","Restore")
	undo.text=Text.phrase("撤销上次恢复","Undo last restore")

func open()->void:
	days.clear()
	error.text=""
	undo.disabled=true
	get_ok_button().disabled=true
	for row in game.world_checkpoints.entries():
		if row.key=="undo":
			undo.disabled=false
			continue
		var icon:Texture2D
		var thumbnail:String=str(row.get("thumbnail",""))
		if not thumbnail.is_empty() and thumbnail.length()<160000:
			var image:=Image.new()
			if image.load_jpg_from_buffer(Marshalls.base64_to_raw(thumbnail))==OK and image.get_size()==Vector2i(144,90):
				icon=ImageTexture.create_from_image(image)
		var index:=days.add_item(Text.phrase("第 %d 天 · %d 处变化","Day %d · %d changes")%[row.day,int(row.get("changes",0))],icon)
		days.set_item_metadata(index,row.key)
	popup_centered()

func apply(key:String,stop_confirmed:bool=false)->void:
	if not stop_confirmed and game.world_checkpoints.working():
		var confirm:=ConfirmationDialog.new()
		confirm.dialog_text=Text.phrase("大家手上的活会先停下。要继续恢复吗？","Everyone will stop what they’re doing before the island is restored. Continue?")
		add_child(confirm)
		confirm.confirmed.connect(func():confirm.queue_free();apply(key,true))
		confirm.canceled.connect(confirm.queue_free)
		confirm.popup_centered()
		return
	var code:String=game.world_checkpoints.restore(key,game.data_dir.path_join("island-v2.json"),stop_confirmed)
	if code.is_empty():
		for id in game.world_door.owners:
			game.world_door.publish(id,"world_restored",{"day":game.world_checkpoints.notice_day,"undo":key=="undo"})
		hide()
	else:
		error.text=Text.phrase("还有活动无法安全停下。这次没有恢复。","An activity couldn’t be stopped safely. The island hasn’t changed.") if code=="busy" else Text.phrase("无法恢复这份快照。","This snapshot could not be restored.")
