extends SceneTree
## Offline transcription of authored brush matrices; existing material files are read-only.
func _initialize()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/brush-source.json"))
	var directory:="res://content/art-studies/textures/"
	for material in ["grass","sand","soil"]:
		for variant in range(3):
			var image:=Image.load_from_file("res://assets/island/"+material+".png");image.convert(Image.FORMAT_RGBA8)
			if variant==1:image.flip_x()
			if variant==2:image.flip_y()
			for index in range(source.placements.size()):
				var origin:Array=source.placements[(index+variant*3)%source.placements.size()]
				for y in range(source.rows.size()):
					for x in range(source.rows[y].length()):
						var mark:String=source.rows[y][x]
						if mark==".":continue
						var at:=Vector2i((int(origin[0])+x*3+variant*17)%510,(int(origin[1])+y*3+variant*29)%510)
						var color:=Color(source.palettes[material][(int(mark)+variant)%3]);color.a=.38
						for dy in range(2):
							for dx in range(2):image.set_pixelv(at+Vector2i(dx,dy),image.get_pixelv(at+Vector2i(dx,dy)).blend(color))
			image.save_png(directory+material+"-"+str(variant)+".png")
	for index in range(3):
		var image:=Image.create(64,48,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
		for y in range(source.rows.size()):
			for x in range(source.rows[y].length()):
				var mark:String=source.rows[y][x]
				if mark==".":continue
				var color:=Color(source.palettes["grass" if (x+y+index)%3 else "sand"][(int(mark)+index)%3]);color.a=.32
				image.fill_rect(Rect2i(x*4,y*4,2+index%2,2),color)
		image.save_png(directory+"transition-"+str(index)+".png")
		var coast:=Image.create(64,48,false,Image.FORMAT_RGBA8);coast.fill(Color.TRANSPARENT)
		for y in range(source.rows.size()):
			for x in range(source.rows[y].length()):
				var mark:String=source.rows[y][x]
				if mark==".":continue
				var color:=Color(source.palettes.sand[(int(mark)+index)%3]);color.a=.30
				coast.fill_rect(Rect2i(x*4,y*4,3,2),color)
		coast.save_png(directory+"coast-"+str(index)+".png")
	var stone:=Image.load_from_file("res://content/art-studies/textures/soil-0.png").get_region(Rect2i(0,0,64,64));stone.convert(Image.FORMAT_RGBA8)
	var colors:=[Color("a8aa96"),Color("bfc0ac"),Color("949c89"),Color("cec9b1")]
	for index in range(source.stone_shapes.size()):
		var shape:=PackedVector2Array()
		for point in source.stone_shapes[index]:shape.append(Vector2(point[0],point[1]))
		for y in range(64):
			for x in range(64):
				if Geometry2D.is_point_in_polygon(Vector2(x,y),shape):
					var color:Color=colors[index%4]
					if not Geometry2D.is_point_in_polygon(Vector2(x-1,y-1),shape):color=color.lightened(.12)
					elif not Geometry2D.is_point_in_polygon(Vector2(x+1,y+1),shape):color=color.darkened(.18)
					stone.set_pixel(x,y,color)
	stone.save_png(directory+"stone.png");print("Authored study textures: 9 material variants +6 transition brushes +1 flagstone");quit()
