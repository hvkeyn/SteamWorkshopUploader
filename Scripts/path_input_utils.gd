class_name PathInputUtils
extends RefCounted

## Normalizes pasted paths: quotes, file:// URLs, Windows slashes.


static func normalize_directory_path(raw: String) -> String:
	var path := raw.strip_edges()
	if path.is_empty():
		return ""

	if path.length() >= 2:
		var first := path[0]
		var last := path[path.length() - 1]
		if (first == '"' and last == '"') or (first == "'" and last == "'"):
			path = path.substr(1, path.length() - 2).strip_edges()

	if path.begins_with("file:///"):
		path = path.substr(8)
	elif path.begins_with("file://"):
		path = path.substr(7)

	path = path.replace("%20", " ")
	path = path.replace("\\", "/")

	# "/E:/Games/mod" -> "E:/Games/mod"
	if path.length() >= 3 and path[0] == "/" and path[2] == ":":
		path = path.substr(1)

	return path.rstrip("/")


static func is_existing_directory(path: String) -> bool:
	return not path.is_empty() and DirAccess.dir_exists_absolute(path)
