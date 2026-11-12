extends SceneTree
const Owners=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl"]
const Contact=preload("res://scripts/cat_contact_art.gd")
const House=preload("res://scripts/house_appearance.gd")
var failed:=false
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var library=preload("res://scripts/character_library.gd").new();library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var art=Contact.new();var count:=0
	for owner in Owners:
		for direction in ["down","up","left","right"]:
			for action in ["hold","pet"]:
				for column in range(3 if action=="hold" else 2):
					var image:=Image.load_from_file("res://assets/cat-contact-redraw/%s-%s-%s-%d.png"%[owner,action,direction,column])
					check(image!=null and image.get_size()==Vector2i(96,128),"new full body canvas")
					if image==null:continue
					check(image.get_pixel(0,0).a==0 and image.get_pixel(95,127).a==0,"transparent corners")
					var used:=image.get_used_rect()
					check(used.size.y>=45 and used.end.y<=128 and used.position.y>=0,"whole body stays in canvas/foot")
					var actor:Dictionary={"appearance_id":owner,"id":"human","facing":direction}
					var rendered:Texture2D=art.texture(library,actor,action,column)
					check(rendered!=null and rendered.get_image().get_size()==image.get_size(),"runtime selects new body")
					check(image.get_data()!=library.texture(owner,direction+"_0").get_image().get_data(),"new body differs from idle")
					count+=1
	for owner in House.OWNERS:
		var site:Dictionary={"owner_id":owner,"house_appearance":"personal"}
		var next:Texture2D=House.texture(site,library)
		site.house_appearance="personal_legacy";var legacy:Texture2D=House.texture(site,library)
		check(House.enabled(site) and next.get_image().get_data()!=legacy.get_image().get_data(),"new/legacy distinct")
		site.house_appearance="classic";check(not House.enabled(site),"classic selects original blueprint")
	check(count==100,"100 imported contact PNGs")
	print("REDRAW ART ",count," PNGs ",not failed)
	quit(1 if failed else 0)
