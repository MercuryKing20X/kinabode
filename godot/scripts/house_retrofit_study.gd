extends "res://scripts/island_art_study.gd"
## Art review only: full source masters + copied cutouts. No simulation or save path.
var comparison_id:=""
func _ready()->void:
	get_window().content_scale_size=Vector2i.ZERO
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	config=JSON.parse_string(FileAccess.get_file_as_string("res://content/house-retrofits/street.json"))
	style=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-style.json"))
	ground.prepare(config);props.build(style)
	if comparison_id.is_empty():
		for h in config.houses:add_house(h.id,Vector2(h.position[0],h.position[1]))
		for p in config.props:
			var texture:Texture2D;var anchor:Vector2
			if p.kind=="scenery":
				texture=load("res://assets/island/"+p.asset+".png");anchor=Vector2(texture.get_width()/2,texture.get_height()-8)
			else:texture=props.textures[p.kind];anchor=props.anchors[p.kind]
			entries.append({"type":"prop","value":p,"point":Vector2(p.position[0],p.position[1])*32,"texture":texture,"anchor":anchor,"scale":1})
	else:
		config.camera=[44,37]
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/house-retrofits/manifest.json"))
		add_house(comparison_id,Vector2(38,40),str(manifest.houses[comparison_id].parent))
		add_house(comparison_id,Vector2(50,40))
	entries.sort_custom(func(a,b):return a.point.y<b.point.y)
	ready_for_capture=true;queue_redraw()
func add_house(id:String,point:Vector2,master:String="")->void:
	var path:String="res://content/house-retrofits/houses/"+id+".json" if master.is_empty() else "res://content/works/"+master+".json"
	var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));assert(library.valid(art))
	if not art.has("openings"):art.openings={"windows":[[48,143,37,42],[177,141,27,40],[134,105,35,38]]}
	library.artworks[art.id]=art
	entries.append({"type":"house","value":{"id":id},"point":point*32,"texture":library.texture(art.id,"stage_4"),"anchor":Vector2(art.anchor[0],art.anchor[1]),"scale":1,"art":art})
