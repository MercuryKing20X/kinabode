extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1152,680);root.content_scale_size=Vector2i.ZERO
	var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var atlas:=preload("res://scripts/motion_atlas.gd").new()
	var a:Dictionary={"id":"human","role":"human","facing":"left","appearance_id":"suit-hulk"}
	var bg:=ColorRect.new();bg.color=Color("7d9174");bg.size=Vector2(1152,680);root.add_child(bg)
	for action in ["walk","run","chop","gather","eat","farm","gesture","cat"]:
		var pane:=Control.new();root.add_child(pane)
		for row in 4:
			a.facing=["down","left","right","up"][row]
			for col in (6 if action=="cat" else int(atlas.manifests[action].columns)):
				var t:=TextureRect.new()
				if action=="cat":t.texture=ImageTexture.create_from_image(Image.load_from_file("res://assets/cat-contact-redraw/suit-hulk-%s-%s-%d.png"%["hold" if col<3 else "pet",a.facing,col%3]))
				else:t.texture=atlas.texture(action,lib,a,col)
				assert(t.texture!=null);t.position=Vector2(12+col*110,row*160);t.size=Vector2(96,128);t.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;pane.add_child(t)
		var l:=Label.new();l.text=action+" | actual Godot pixel viewport, material preview";l.position=Vector2(12,645);pane.add_child(l)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join("viewport-"+action+".png"))
		pane.queue_free();await process_frame
	print("SUIT_V2_VIEWPORT PASS 8 action previews")
	quit()
