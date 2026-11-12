extends Node
var game:Node
var menu:AcceptDialog
var checks:Dictionary={}
var target_id:=""
func setup(host:Node)->void:game=host;name="ResortUI"
func text(zh:String,en:String)->String:return en if TranslationServer.get_locale().begins_with("en") else zh
func show_target(id:String)->void:
	if is_instance_valid(menu):menu.queue_free()
	target_id=id;checks.clear();menu=AcceptDialog.new();game.add_child(menu)
	menu.title=text(preload("res://scripts/localization.gd").source("content.health_20261107.ef326aebbfec"),"Holiday together");menu.ok_button_text=text(preload("res://scripts/localization.gd").source("content.health_20261107.3fd47edce45b"),"Close")
	var box:=VBoxContainer.new();menu.add_child(box);box.custom_minimum_size.x=380
	var villa:Dictionary=game.world.resort.villa(id)
	if not villa.is_empty():
		menu.title=villa.name_en if TranslationServer.get_locale().begins_with("en") else villa.name
		var enter:=Button.new();enter.focus_mode=Control.FOCUS_NONE;box.add_child(enter);enter.text=text(preload("res://scripts/localization.gd").source("content.health_20261107.ddba60966231"),"Come inside")
		enter.pressed.connect(func():
			leave();game.status.text=str(game.world.command("human",{"intent":"enter","target_id":id}).get("message",""));menu.hide())
	else:
		var everyone:=CheckBox.new();everyone.focus_mode=Control.FOCUS_NONE;box.add_child(everyone);everyone.text=text(preload("res://scripts/localization.gd").source("content.command_grammar.token_9"),"Everyone");everyone.button_pressed=true
		for actor in game.world.actors:
			if actor=="human":continue
			var c:=CheckBox.new();c.focus_mode=Control.FOCUS_NONE;box.add_child(c);c.text=preload("res://scripts/localization.gd").resident(game.world,actor);c.button_pressed=true;checks[actor]=c
		everyone.toggled.connect(func(on):
			for c in checks.values():c.button_pressed=on)
		var start:=Button.new();start.focus_mode=Control.FOCUS_NONE;box.add_child(start)
		var kind:String=game.world.resort.activities[id].kind
		start.text=text({"lounge":preload("res://scripts/localization.gd").source("content.health_20261107.e5c4fe71239e"),"pool":preload("res://scripts/localization.gd").source("content.health_20261107.be792f7f12e1"),"swing":preload("res://scripts/localization.gd").source("content.health_20261107.e81fb9c23f41"),"hammock":preload("res://scripts/localization.gd").source("content.health_20261107.e1162a98a792")}.get(kind,preload("res://scripts/localization.gd").source("content.health_20261107.64e127f5732c")),{"lounge":"Lie down","pool":"Play in the pool","swing":"Swing together","hammock":"Rest in hammocks"}.get(kind,"Take a rest"))
		start.pressed.connect(func():
			leave()
			var ids:Array=["human"]
			for actor in checks:
				if checks[actor].button_pressed:ids.append(actor)
			var result:Dictionary=game.world.resort.begin(id,ids)
			if result.ok:
				var failures:Array=[]
				for actor in result.rejected:failures.append(preload("res://scripts/localization.gd").resident(game.world,actor)+": "+text({"very_hungry":preload("res://scripts/localization.gd").source("content.health_20261107.9dddc14d8670"),"busy":preload("res://scripts/localization.gd").source("content.health_20261107.5110aa71b985"),"not_on_island":preload("res://scripts/localization.gd").source("content.health_20261107.ec7bcd226f29"),"full":preload("res://scripts/localization.gd").source("content.health_20261107.3419a448b625"),"unreachable":preload("res://scripts/localization.gd").source("content.health_20261107.b2b0aca7950b")}.get(result.rejected[actor],preload("res://scripts/localization.gd").source("content.health_20261107.3d79405afdc3")),{"very_hungry":"Too hungry","busy":"Busy","not_on_island":"Not on the island yet","full":"No free seat","unreachable":"Cannot reach the seat"}.get(result.rejected[actor],"Unavailable")))
				game.status.text=text(preload("res://scripts/localization.gd").source("content.health_20261107.c4ce68283f64"),"Time to relax together!") if failures.is_empty() else "；".join(failures)
			else:game.status.text=str(result)
			menu.hide())
	menu.popup_centered()
func leave()->void:
	var w:RefCounted=game.world
	var job:Dictionary=w.work.jobs.get("human",{})
	if job.get("intent")!="resort":return
	var target:String=job.target_id
	for id in w.work.jobs.keys():
		if w.work.jobs[id].get("intent")=="resort" and w.work.jobs[id].get("target_id")==target:w.work.stop(id,false)
