extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(576,128);root.content_scale_size=Vector2i.ZERO
	var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var atlas:=preload("res://scripts/motion_atlas.gd").new()
	for action in ["walk","chop","gather"]:
		for id in atlas.manifests[action].works:
			if atlas.manifests[action].works[id].status!="independent":continue
			var node:=Node2D.new();root.add_child(node)
			for col in int(atlas.manifests[action].columns):
				var sprite:=Sprite2D.new();sprite.texture=atlas.texture(action,lib,{"appearance_id":id,"facing":"left"},col);sprite.centered=false;sprite.position=Vector2(col*96,0);sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;node.add_child(sprite)
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/youqi-actions-review/viewport-"+action+"-"+id+".png")
			node.queue_free();await process_frame
	print("ATLAS_VIEWPORT PASS");quit()
