extends RefCounted
## Imported textures are remapped inside PCKs; user images remain ordinary files.
static func read(path:String)->Image:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var texture:Resource=load(path)
		if texture is Texture2D:return texture.get_image()
	return Image.load_from_file(path)

static func exists(path:String)->bool:
	return ResourceLoader.exists(path) if path.begins_with("res://") else FileAccess.file_exists(path)
