extends RefCounted
## Art-only reuse and authored additions. No inventory/facility instances.
var base:RefCounted=preload("res://scripts/island_sample_props.gd").new()
var textures:Dictionary={}
var anchors:Dictionary={}
func commit(id:String,anchor:Vector2i)->void:
	textures[id]=ImageTexture.create_from_image(base.image);anchors[id]=Vector2(anchor)
func build(style:Dictionary)->void:
	base.build(style);textures=base.textures.duplicate();anchors=base.anchors.duplicate()
	var rock:Image=load("res://assets/island/rock.png").get_image();var logs:Image=load("res://assets/island/logs.png").get_image()
	for id in ["well","bench","notice"]:
		var image:Image=textures[id].get_image()
		if id=="well":image.resize(192,224,Image.INTERPOLATE_NEAREST);anchors[id]=Vector2(96,216)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var c:=image.get_pixel(x,y)
				if c.a<.9:continue
				var material:Image=rock if absf(c.r-c.g)<.12 and absf(c.g-c.b)<.12 else logs
				var stroke:Color=material.get_pixel((x+13)%material.get_width(),(y+37)%material.get_height())
				if stroke.a>.9:image.set_pixel(x,y,c.lerp(Color(stroke.r,stroke.g,stroke.b,c.a),.18))
		textures[id]=ImageTexture.create_from_image(image)
	base.image=Image.create(22,28,false,Image.FORMAT_RGBA8);base.image.fill(Color.TRANSPARENT)
	base.polygon([[3,10],[19,10],[17,25],[5,25]],34);base.ellipse(Rect2i(2,7,18,7),27);base.ellipse(Rect2i(4,8,14,4),1)
	for x in [5,10,15]:base.line(Vector2i(x,13),Vector2i(x,22),37)
	base.line(Vector2i(4,9),Vector2i(6,2),27,2);base.line(Vector2i(6,2),Vector2i(16,2),30,2);base.line(Vector2i(16,2),Vector2i(18,9),27,2);commit("bucket",Vector2i(11,25))
	base.image=Image.create(132,100,false,Image.FORMAT_RGBA8);base.image.fill(Color.TRANSPARENT)
	base.wood(9,23,7,72);base.wood(116,23,7,72);base.polygon([[1,26],[19,4],[111,4],[131,26],[127,32],[109,15],[22,15],[5,32]],35)
	for point in [Vector2i(8,19),Vector2i(33,7),Vector2i(65,5),Vector2i(96,8),Vector2i(118,20),Vector2i(12,49),Vector2i(119,68)]:
		base.ellipse(Rect2i(point-Vector2i(10,5),Vector2i(23,14)),10);base.ellipse(Rect2i(point-Vector2i(6,8),Vector2i(14,13)),13);base.ellipse(Rect2i(point-Vector2i(3,6),Vector2i(9,8)),42);base.rect(point.x,point.y-3,3,3,47)
	commit("flower_arch",Vector2i(66,96))
	base.image=Image.create(140,150,false,Image.FORMAT_RGBA8);base.image.fill(Color.TRANSPARENT)
	for x in [9,124]:base.wood(x,13,7,132)
	base.wood(3,9,134,9)
	for x in [38,101]:base.line(Vector2i(x,20),Vector2i(x,112),27,2)
	for y in [83,93,103]:base.wood(31,y,79,7)
	base.wood(27,115,87,10);base.wood(27,109,8,11);base.wood(106,109,8,11);commit("swing_chair",Vector2i(70,146))
	base.image=Image.create(64,56,false,Image.FORMAT_RGBA8);base.image.fill(Color.TRANSPARENT)
	base.wood(7,18,52,10);base.wood(11,28,6,23);base.wood(49,28,6,23);base.rect(21,11,28,12,23);base.line(Vector2i(27,15),Vector2i(42,15),19);base.line(Vector2i(27,18),Vector2i(37,18),19);commit("note_table",Vector2i(32,52))
	base.image=Image.create(160,104,false,Image.FORMAT_RGBA8);base.image.fill(Color.TRANSPARENT)
	base.wood(6,7,6,92);base.wood(149,7,6,92);base.line(Vector2i(10,14),Vector2i(152,19),33)
	for x in [27,62,101]:base.polygon([[x,17],[x+21,18],[x+25,34],[x+19,35],[x+18,61],[x+3,60],[x+3,35],[x-4,34]],42 if x==62 else 30)
	commit("clothesline",Vector2i(80,100))

	# Small field marker uses the same wood/straw/fabric palette as existing props.
	base.image=Image.create(48,64,false,Image.FORMAT_RGBA8);base.image.fill(Color.TRANSPARENT)
	base.wood(22,24,5,36);base.wood(6,28,36,4);base.rect(16,24,17,20,35);base.rect(20,10,10,13,39);base.rect(11,10,28,4,38);base.rect(17,5,16,7,38);base.rect(16,43,7,12,33);base.rect(27,43,6,12,33)
	commit("scarecrow",Vector2i(24,60))
