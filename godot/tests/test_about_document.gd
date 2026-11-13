extends "res://tests/test_simple_connection_input.gd"
class DocumentFixture extends "res://scripts/about_panel.gd":
	var directory:String
	func document_path(english:bool)->String:
		return directory.path_join("about.en.md" if english else "about.md")
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR").path_join("docs-fixture")
	DirAccess.make_dir_recursive_absolute(directory)
	var source:String=ProjectSettings.globalize_path("res://").path_join("../docs/about.md").simplify_path()
	var copied:String=directory.path_join("about.md")
	check(DirAccess.copy_absolute(source,copied)==OK,"copy complete authoritative Chinese document")
	var authoritative:PackedByteArray=FileAccess.get_file_as_bytes(source)
	var fixture_bytes:PackedByteArray=FileAccess.get_file_as_bytes(copied)
	check(not authoritative.is_empty() and fixture_bytes==authoritative,"fallback fixture bytes equal whole authoritative document")
	print("ABOUT_FALLBACK_INPUT ",JSON.stringify({"authority_bytes":authoritative.size(),"fixture_bytes":fixture_bytes.size(),"authority_sha256":FileAccess.get_sha256(source),"fixture_sha256":FileAccess.get_sha256(copied)}))
	# Install before constructing any panel or lazy connection overview.
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,OS.get_environment("HABITAT_DATA_DIR"))
	pool.factory=func(_id):return Stub.new()
	preload("res://scripts/localization.gd").select(OS.get_environment("HABITAT_DATA_DIR"),"en")
	var panel:=DocumentFixture.new();panel.directory=directory;root.add_child(panel);panel.open();await frames()
	var text:String=panel.body.get_parsed_text()
	check(text.begins_with("暂无英文 / English coming soon"),"English missing fallback notice first")
	# The author replaced the old section heading before v0.6.0 publication.
	# Verify her actual first paragraph, while retaining the contact anchor.
	var author_anchor:String="本作由ChatGPT 6.1 Sol 编写，游戏会持续更新 ，已经在GitHub开源，有想法自己实现，有地图自己拓展，有bug自己修复。"
	check(author_anchor in text and "MercuryFantasy" in text,"fallback loads whole Chinese document")
	check("关于有栖（Kinabode）" in text,"fallback renders authoritative Chinese document head")
	check("2026年11月    水星" in text,"fallback renders authoritative Chinese document tail")
	print("ABOUT_FALLBACK_RENDER ",JSON.stringify({"characters":text.length(),"head":"关于有栖（Kinabode）" in text,"author_first_paragraph":author_anchor in text,"contact":"MercuryFantasy" in text,"tail":"2026年11月    水星" in text}))
	check(panel._inline("**strong** [site](https://example.com)")=="[b]strong[/b] [url=https://example.com]site[/url]","bold and browser link markup")
	check(panel._inline("[url=bad]literal").begins_with("[lb]url=bad]"),"document text cannot inject BBCode")
	var im:=Image.create(4,4,false,Image.FORMAT_RGBA8);im.fill(Color.RED);im.save_png(directory.path_join("optional.png"))
	var file:=FileAccess.open(directory.path_join("about.en.md"),FileAccess.WRITE)
	file.store_string("# Heading\n\n## Section\n\n### Subsection\n\nParagraph **bold**\n\n- List\n\n---\n\n[site](https://example.com)\n\n![optional](optional.png)\n");file.close()
	panel.show_document();await frames()
	text=panel.body.get_parsed_text()
	check("Heading" in text and "Section" in text and "Subsection" in text,"all heading levels")
	check("Paragraph bold" in text and "• List" in text and "────" in text,"paragraph bold list separator")
	check(not "English coming soon" in text,"existing English used")
	panel.queue_free();await frames();print("ABOUT_DOCUMENT checks=",checks," failed=",failed);quit(1 if failed else 0)
