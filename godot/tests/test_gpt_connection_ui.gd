extends SceneTree
var failed:=false
func _initialize()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(1280,800)
	var panel:=preload("res://scripts/connection_overview.gd").new();root.add_child(panel)
	var theme_data:=Theme.new();theme_data.default_font=preload("res://assets/fonts/NotoSansSC.ttf");panel.theme=theme_data
	panel.setup(OS.get_environment("HABITAT_DATA_DIR"));panel.open()
	panel.advanced=true;panel.refresh()
	await process_frame
	var pool:Node=panel.pool
	pool.api_usage.clear()
	pool.set_api("codex","openai");panel.refresh();await process_frame;await process_frame
	var picker:OptionButton=panel.find_child("api_codex",true,false)
	if picker==null or picker.selected!=2:failed=true
	var key:LineEdit=panel.find_child("GPTKey",true,false)
	if key==null or not key.secret:failed=true
	if key!=null:
		for down in [true,false]:
			var click:=InputEventMouseButton.new();click.position=key.get_global_rect().get_center();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down;root.push_input(click,true);await process_frame
		for letter in "stub":
			var press:=InputEventKey.new();press.pressed=true;press.unicode=letter.unicode_at(0);root.push_input(press,true);await process_frame
		if key.text!="stub":failed=true;print("GPT_INPUT_NOT_DELIVERED")
		key.clear()
	pool.settings.set_value("openai","models",["gpt-6.1-sol","gpt-6.1-terra"]);panel.refresh();await process_frame;await process_frame
	var actual:OptionButton=panel.find_child("GPTModel_chat",true,false)
	if actual==null or actual.item_count!=2 or actual.get_item_text(actual.selected)!="gpt-6.1-terra":failed=true
	for locale in ["zh_CN","en"]:
		TranslationServer.set_locale(locale);panel.refresh();await process_frame;await process_frame
		if DisplayServer.get_name()!="headless":
			RenderingServer.force_draw(false);root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join("gpt-"+locale+".png"))
			var scroll:ScrollContainer=panel.get_child(0);scroll.scroll_vertical=10000;await process_frame
			RenderingServer.force_draw(false);root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join("gpt-"+locale+"-usage.png"))
			scroll.scroll_vertical=0
	pool.receive("codex",{"kind":"usage","complete":true,"model":"gpt-6.1-terra","total_tokens":110,"input_tokens":100,"output_tokens":10,"turn_key":"gpt-ui-first","scope":"direct","estimated_usd":.0001})
	if pool.api_tokens()!=110 or not is_equal_approx(pool.api_cost(),.0001):failed=true
	pool.settings.set_value("openai","limit",120)
	pool.receive("codex",{"kind":"usage","complete":true,"model":"gpt-6.1-terra","total_tokens":10,"input_tokens":8,"output_tokens":2,"turn_key":"gpt-ui-second","scope":"direct","estimated_usd":.0001})
	await process_frame
	if pool.connect_ai("codex")!=null:failed=true
	pool.receive("codex",{"kind":"error","code":"openai_auth","message":"密钥无效（401）；请重新填写密钥。"});await process_frame;await process_frame
	if pool.states.codex.state!="error" or not "401" in pool.states.codex.error or pool.links.has("codex"):failed=true
	print("GPT_UI failed=",failed)
	panel.queue_free();await process_frame;quit(1 if failed else 0)
