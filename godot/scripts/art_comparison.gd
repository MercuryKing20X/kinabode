extends RefCounted
## Explicit evidence-only lossless join; never edits either source viewport.
static func join(left:Image,right:Image)->Image:
	if left==null or right==null or left.get_size()!=right.get_size():return null
	var a:Image=left.duplicate();var b:Image=right.duplicate();a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
	var result:=Image.create(a.get_width()*2,a.get_height(),false,Image.FORMAT_RGBA8)
	result.blit_rect(a,Rect2i(Vector2i.ZERO,a.get_size()),Vector2i.ZERO);result.blit_rect(b,Rect2i(Vector2i.ZERO,b.get_size()),Vector2i(a.get_width(),0));return result
static func same_camera(a:Dictionary,b:Dictionary)->bool:
	for record in [a,b]:
		if not record.get("camera_tile") is Array or record.camera_tile.size()!=2 or not record.get("pixels") is Array or record.pixels.size()!=2:return false
	return a.get("world_pixels_per_tile")==b.get("world_pixels_per_tile") and Vector2(a.camera_tile[0],a.camera_tile[1])==Vector2(b.camera_tile[0],b.camera_tile[1]) and Vector2(a.pixels[0],a.pixels[1])==Vector2(b.pixels[0],b.pixels[1])
