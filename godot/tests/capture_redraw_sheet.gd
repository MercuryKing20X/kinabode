extends SceneTree
const Owners=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl"]
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(640,950);root.content_scale_size=Vector2i.ZERO
	var background:=ColorRect.new();background.color=Color("647c6a");background.size=Vector2(640,950);root.add_child(background)
	for pose in ["hold-0","hold-1","hold-2","pet-0","pet-1"]:
		var frame:=Control.new();root.add_child(frame)
		var title:=Label.new();title.text="Material viewport preview only · "+pose;title.position=Vector2(12,4);frame.add_child(title)
		for row in range(5):
			for col in range(4):
				var direction:String=["down","up","left","right"][col]
				var image:=TextureRect.new();image.texture=ImageTexture.create_from_image(Image.load_from_file("res://assets/cat-contact-redraw/%s-%s-%s-%s.png"%[Owners[row],pose.get_slice("-",0),direction,pose.get_slice("-",1)]));image.position=Vector2(25+col*155,44+row*180);image.size=Vector2(96,128);image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;frame.add_child(image)
				var label:=Label.new();label.text=Owners[row].trim_suffix("-girl")+" "+direction;label.add_theme_font_size_override("font_size",12);label.position=Vector2(5+col*155,174+row*180);frame.add_child(label)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("HABITAT_PLAYTEST_CAPTURE").path_join("redraw-sheet-"+pose+".png"))
		frame.queue_free();await process_frame
	quit()
