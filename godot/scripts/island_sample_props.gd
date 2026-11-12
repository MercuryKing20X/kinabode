extends RefCounted
## Original deterministic pixel primitives, baked once. No world/item identities.
var palette:Array=[]
var image:Image
var textures:Dictionary={}
var anchors:Dictionary={}
func col(i:int)->Color:return Color(palette[i].hex)
func rect(x:int,y:int,w:int,h:int,i:int)->void:
	var area:=Rect2i(x,y,w,h).intersection(Rect2i(0,0,image.get_width(),image.get_height()))
	if area.has_area():image.fill_rect(area,col(i))
func line(a:Vector2i,b:Vector2i,i:int,width:int=1)->void:
	var count:=maxi(absi(a.x-b.x),absi(a.y-b.y))
	for n in range(count+1):
		var at:Vector2i=Vector2(a).lerp(Vector2(b),float(n)/maxi(1,count)).round()
		rect(at.x,at.y,width,width,i)
func ellipse(box:Rect2i,i:int,alpha:float=1)->void:
	var center:=Vector2(box.position)+Vector2(box.size)/2
	for y in range(maxi(0,box.position.y),mini(image.get_height(),box.end.y)):
		for x in range(maxi(0,box.position.x),mini(image.get_width(),box.end.x)):
			if ((Vector2(x,y)-center)/(Vector2(box.size)/2)).length_squared()<=1:
				var value:=col(i);value.a=alpha;image.set_pixel(x,y,image.get_pixel(x,y).blend(value))
func polygon(points:Array,i:int)->void:
	var shape:=PackedVector2Array()
	for p in points:shape.append(Vector2(p[0],p[1]))
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if Geometry2D.is_point_in_polygon(Vector2(x,y),shape):image.set_pixel(x,y,col(i))
func wood(x:int,y:int,w:int,h:int)->void:
	rect(x,y,w,h,33);rect(x+2,y+2,w-4,h-4,35);rect(x+2,y+2,w-4,2,38)
	for py in range(y+7,y+h-2,8):line(Vector2i(x+3,py),Vector2i(x+w-4,py),34)
func crate(x:int,y:int)->void:
	wood(x,y,34,31);line(Vector2i(x+3,y+3),Vector2i(x+29,y+26),37,3);rect(x+2,y+2,30,3,38)
func build(style:Dictionary)->void:
	palette=style.palette
	var sizes={"well":[96,112],"notice":[112,112],"lamp":[48,144],"planter":[64,44],"bench":[128,64],"crates":[80,80],"grass":[48,32],"flowers":[48,32],"mailbox":[48,72],"telescope":[64,80],"bookshelf":[64,72],"windchime":[32,64],"campfire":[96,72],"placard":[56,44],"light":[160,112]}
	for id in sizes:
		image=Image.create(sizes[id][0],sizes[id][1],false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
		match id:
			"well":
				ellipse(Rect2i(7,65,84,42),24);ellipse(Rect2i(9,61,80,39),27);ellipse(Rect2i(15,65,68,27),30);ellipse(Rect2i(22,68,54,20),1);ellipse(Rect2i(26,72,44,12),4)
				for x in [15,33,52,71]:rect(x,90,2,9,25)
				for x in [12,77]:wood(x,25,8,70)
				polygon([[3,29],[47,3],[93,29],[87,35],[47,14],[9,35]],32);polygon([[6,27],[47,5],[91,27],[85,30],[47,12],[13,31]],35)
				for x in range(13,86,9):line(Vector2i(x,27),Vector2i(47,9),34)
				wood(17,31,63,8);line(Vector2i(49,36),Vector2i(49,69),38,2);wood(42,62,15,14);rect(44,63,11,2,39)
			"notice":
				for x in [15,87]:wood(x,55,9,52)
				wood(5,15,101,65);rect(12,22,87,48,33);rect(17,27,36,36,23);rect(60,29,31,29,31);rect(16,11,83,5,38)
				for y in [38,45,52]:rect(23,y,23-(y%3)*4,2,19)
				rect(69,35,14,12,42);rect(69,49,17,2,28)
				polygon([[0,17],[14,6],[99,6],[111,17]],33);rect(12,8,86,3,37)
			"lamp":
				rect(19,45,10,92,24);rect(21,47,3,87,27);rect(14,132,20,6,24)
				rect(9,16,30,37,24);rect(12,19,24,28,46);rect(16,22,15,21,47);rect(21,19,3,28,35);rect(11,33,25,3,35)
				polygon([[6,17],[24,4],[42,17]],24);line(Vector2i(11,15),Vector2i(24,7),28,2);rect(8,50,31,4,35)
			"planter":
				polygon([[10,21],[55,21],[49,40],[17,40]],33);polygon([[13,23],[52,23],[47,37],[19,37]],36);rect(8,18,49,7,37);rect(11,18,43,2,39)
				for x in [17,29,42,50]:
					ellipse(Rect2i(x-8,6,16,17),9);ellipse(Rect2i(x-6,3,13,13),13);ellipse(Rect2i(x-5,1,9,9),42);rect(x-2,4,3,3,47)
			"bench":
				for x in [15,103]:wood(x,22,8,36)
				for y in [4,13,22]:wood(9,y,110,7)
				wood(4,35,120,10);rect(8,36,112,2,39);line(Vector2i(8,42),Vector2i(119,42),33)
			"crates":crate(6,43);crate(40,43);crate(24,13)
			"grass":
				for point in [[8,25],[19,27],[28,26],[37,24]]:
					var x:int=point[0];var y:int=point[1]
					polygon([[x-7,y],[x-8,y-13],[x-2,y-5],[x+1,y-22],[x+4,y-7],[x+10,y-13],[x+6,y]],10);line(Vector2i(x,y-2),Vector2i(x+1,y-16),14)
			"flowers":
				for point in [[7,24],[18,18],[30,26],[40,16]]:
					var x:int=point[0];var y:int=point[1]
					line(Vector2i(x,y),Vector2i(x,y-10),10,2);ellipse(Rect2i(x-5,y-16,11,9),42 if x%2 else 46);rect(x-1,y-13,3,3,47)
			"mailbox":
				wood(22,31,7,35);wood(7,10,34,25);rect(9,12,29,19,4);rect(10,12,27,2,6);rect(10,31,29,3,1);rect(25,20,9,2,1)
				rect(37,6,3,22,33);rect(40,6,7,8,42)
			"telescope":
				line(Vector2i(30,37),Vector2i(12,75),33,4);line(Vector2i(30,37),Vector2i(53,74),33,4);line(Vector2i(30,40),Vector2i(31,76),37,3)
				polygon([[5,31],[46,5],[59,18],[18,46]],24);polygon([[8,30],[46,8],[55,18],[18,41]],28);line(Vector2i(12,28),Vector2i(46,10),31,3);line(Vector2i(7,33),Vector2i(17,44),45,4);ellipse(Rect2i(44,6,13,13),2);ellipse(Rect2i(47,7,5,5),6)
			"bookshelf":
				wood(5,7,54,59);rect(10,12,44,45,33)
				for y in [14,36]:
					for x in range(12,51,7):rect(x,y,5,18-(x%4),40+(x/7)%8);rect(x,y+3,3,2,39)
				wood(7,31,50,5);wood(6,57,52,6)
			"windchime":
				line(Vector2i(16,2),Vector2i(16,17),33);polygon([[3,23],[16,12],[29,23]],4);rect(6,23,21,4,6)
				for x in [8,15,23]:line(Vector2i(x,26),Vector2i(x,46+x%6),27,3)
				line(Vector2i(16,28),Vector2i(16,59),33);rect(12,50,9,12,42)
			"campfire":
				ellipse(Rect2i(5,40,86,27),25);ellipse(Rect2i(9,38,78,21),28);ellipse(Rect2i(18,41,60,15),32)
				for x in [22,37,53,69]:rect(x,57,7,5,26)
				line(Vector2i(25,49),Vector2i(69,60),34,7);line(Vector2i(24,59),Vector2i(68,47),36,7)
				polygon([[29,49],[32,28],[42,39],[47,6],[57,34],[66,22],[68,49],[53,57],[39,55]],44);polygon([[36,49],[45,27],[49,41],[58,32],[61,49],[50,54]],46);polygon([[43,49],[49,38],[54,49],[49,53]],47)
			"placard":wood(25,18,6,22);wood(3,3,50,26);rect(7,7,42,17,23)
			"light":
				for radius in [76,59,43,27]:ellipse(Rect2i(80-radius,56-radius/2,radius*2,radius),46,.04 if radius>50 else .08)
		textures[id]=ImageTexture.create_from_image(image);anchors[id]=Vector2i(image.get_width()/2,image.get_height()-4) if id!="light" else Vector2i(80,56)
