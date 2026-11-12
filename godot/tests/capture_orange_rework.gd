extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
 var bg:=ColorRect.new();bg.color=Color("64756c");bg.size=Vector2(1280,800);root.add_child(bg)
 var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
 var row:=Node2D.new();root.add_child(row)
 for category in ["stand","walk","run","chop","eat","fishing"]:
  for c in row.get_children():c.queue_free()
  await process_frame
  var cols:int=4 if category=="stand" else 6 if category in ["walk","run"] else 5 if category=="chop" else 10 if category=="eat" else 7
  for n in range(cols):
   var sp:=Sprite2D.new();sp.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;sp.centered=false
   if category=="stand":sp.texture=lib.texture("orange-sunflower-girl",["down","up","left","right"][n]+"_0")
   else:
    var t:=AtlasTexture.new();t.atlas=load("res://content/"+category+"-animations/orange-sunflower-girl.png");t.region=Rect2(n*96,128,96,128);sp.texture=t
   sp.scale=Vector2(2,2);sp.position=Vector2(20+n*minf(200,1240.0/cols),200);row.add_child(sp)
  await process_frame;await process_frame;RenderingServer.force_draw(false)
  root.get_texture().get_image().save_png(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("review-"+category+"-viewport.png"))
 print("ORANGE_CATEGORY_VIEWPORTS 6");quit()
