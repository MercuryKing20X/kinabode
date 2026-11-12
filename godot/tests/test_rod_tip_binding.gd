extends SceneTree
const F=preload("res://tests/fishing_fixture.gd")
const MIRRORED_WORKS=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl","ai-gpt","ai-claude","ai-gemini","ai-grok","ai-deepseek","ai-glm","ai-qwen","ai-kimi"]
const ORANGE_SOURCE_SHA="bade0a217dc3f194533de9edb8965151e226d12aa2db4eee61a05527dca1ae19"
const ORANGE_ATLAS_SHA="6eca517f594685d901858bf411eb29ed6c270e14e7e403fd0d5f2a80cbda407f"
const INDEPENDENT_WORKS=["suit-hulk","orange-sunflower-girl"]
const SUIT_SOURCE_SHA="0573630694cd5a2209cda6ae99350fb20c4a7592eb587516f1e7e7c6eedb7113"
const SUIT_ATLAS_SHA="fcb49390b30d35f52b0d149c53258b5f4a088fe13e88ed8a20878cd22db343fc"
var checks:=0
func check(ok:bool,msg:String)->void:
	checks+=1
	assert(ok,msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/fishing-animations/manifest.json"))
	for id in MIRRORED_WORKS:check(manifest.works.has(id),"all original thirteen mirrored works remain covered "+id)
	check(manifest.works.keys().all(func(id):return id in MIRRORED_WORKS or id in INDEPENDENT_WORKS),"every additional directional atlas requires an explicit provenance contract")
	var provenance_path:String=ProjectSettings.globalize_path("res://").path_join("../production/art/suit-hulk-v2-20261106/provenance.json").simplify_path()
	var provenance:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(provenance_path))
	check(provenance.sources["fish-source.png"]==SUIT_SOURCE_SHA and FileAccess.get_sha256(provenance_path.get_base_dir().path_join("fish-source.png"))==SUIT_SOURCE_SHA,"independent four-row source matches original retained provenance and real file hash")
	check(manifest.works["suit-hulk"].provenance=="production/art/suit-hulk-v2-20261106/provenance.json" and FileAccess.get_sha256("res://content/fishing-animations/suit-hulk.png")==SUIT_ATLAS_SHA,"independent four-direction atlas is the original reviewed artifact")
	var orange_provenance_path:String=ProjectSettings.globalize_path("res://").path_join("../production/art/orange-cohesive-20261111/provenance.json").simplify_path()
	var orange_provenance:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(orange_provenance_path))
	check(manifest.works["orange-sunflower-girl"].provenance=="production/art/orange-cohesive-20261111/provenance.json" and orange_provenance.sources["fishing-source.png"]==ORANGE_SOURCE_SHA and FileAccess.get_sha256(orange_provenance_path.get_base_dir().path_join("fishing-source.png"))==ORANGE_SOURCE_SHA,"authorized new independent Orange source has exact provenance and retained source hash")
	check(orange_provenance.assets["fishing-animations/orange-sunflower-girl.png"]==ORANGE_ATLAS_SHA and FileAccess.get_sha256("res://content/fishing-animations/orange-sunflower-girl.png")==ORANGE_ATLAS_SHA,"new independent Orange atlas has its own exact reviewed artifact hash")
	var marked:=0;var fallback:=0
	for id in manifest.works:
		var spec:Dictionary=manifest.works[id];var tex:Texture2D=load("res://content/fishing-animations/"+str(spec.asset));var image:Image=tex.get_image()
		# Import alpha-border color bleeding may fill invisible RGB; compare original authored pixels for exact mirror proof.
		var authored:Image=Image.load_from_file("res://content/fishing-animations/"+str(spec.asset))
		for row in range(4):
			for col in range(7):
				var p:Variant=spec.rod_tips[row][col]
				if p==null:fallback+=1;continue
				check(image.get_pixel(col*96+int(p[0]),row*128+int(p[1])).a>.24,"tip is an existing imported atlas pixel "+id)
				if row==2:
					var left:Image=authored.get_region(Rect2i(col*96,128,96,128));left.flip_x()
					var right:Image=authored.get_region(Rect2i(col*96,256,96,128))
					if id in MIRRORED_WORKS:
						check(p==[95-spec.rod_tips[1][col][0],spec.rod_tips[1][col][1]],"tip mirrors with artwork")
						check(left.get_data()==right.get_data(),"original right artwork really is the exact left mirror "+id)
					else:check(left.get_data()!=right.get_data(),"retained suit right source cell is independently authored, not a mirrored left cell")
				marked+=1
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false)
	await process_frame
	var w:RefCounted=game.world;w.director.set_all_enabled(false)
	check(F.coast(w,"human"),"real World coast route")
	check(w.command("human",{"intent":"fish"}).ok,"real fish task")
	var pose:Dictionary={"scale":Vector2(1.03,.97),"lean":.12,"bob":-1.2,"sway":.4}
	for phase in ["fish_cast","fish_wait","fish_bite","fish_reel"]:
		w.work.jobs.human.phase=phase
		for clock in [0.0,.7,1.5]:
			game.view.clock=clock;w.work.jobs.human.time=clock
			var renderer:RefCounted=game.view.fishing_renderer
			var result:Dictionary=renderer.rod_geometry(game.view,w.actors.human,pose,true)
			var pixel:Array=manifest.works["human-starter"].rod_tips[["down","left","right","up"].find(w.actors.human.facing)][renderer.animation_column(game.view,w.work.jobs.human)]
			var local:Vector2=(Vector2(pixel[0]+.5,pixel[1]+.5)-Vector2(48,120))*game.view.zoom*pose.scale
			var expected:Vector2=game.view.screen(w.point(w.actors.human))+Vector2(pose.sway,pose.bob)*game.view.zoom+local.rotated(pose.lean)
			check(result.tip.distance_to(expected)<.001,"line uses exact transformed frame anchor, including pull")
	# Projection fixture: every appearance x 4 directions x 7 cells.
	# No fish grants or player-save writes; this is not player input.
	var actor:Dictionary=w.actors.human
	for appearance in manifest.works:
		actor.appearance_id=appearance
		for row in range(4):
			actor.facing=["down","left","right","up"][row]
			for col in range(7):
				var j:Dictionary=w.work.jobs.human
				if col<3:j.phase="fish_cast";j.time=(col+.1)*float(w.fishing.rules.cast_seconds)/3;game.view.clock=0
				elif col<5:j.phase="fish_wait";j.time=0;game.view.clock=0 if col==3 else .8
				else:j.phase="fish_reel";j.time=0;game.view.clock=0 if col==5 else .4
				var renderer:RefCounted=game.view.fishing_renderer
				check(renderer.animation_column(game.view,j)==col,"real frame selector covers cell")
				check(renderer.animation_texture(game.view,actor)!=null,"built-in unchanged work uses imported atlas")
				var result:Dictionary=renderer.rod_geometry(game.view,actor,pose,true)
				var p:Array=manifest.works[appearance].rod_tips[row][col]
				var local:Vector2=(Vector2(p[0]+.5,p[1]+.5)-Vector2(48,120))*game.view.zoom*pose.scale
				var expected:Vector2=game.view.screen(w.point(actor))+Vector2(pose.sway,pose.bob)*game.view.zoom+local.rotated(pose.lean)
				check(result.tip.distance_to(expected)<.001,"all 364 line endpoints exactly match the transformed authored anchor")
	print("Rod anchors: ",checks," checks; marked=",marked," fallback=",fallback)
	game.queue_free();await process_frame;quit()
