extends RefCounted

## Known workshop file IDs per app (includes hidden/unpublished items Steam omits from PUBLISHED list).

const SAVE_PATH := "user://ugc_known_items.json"
const REMOVED_KEY := "__removed__"

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func get_ids_for_app(app_id: int) -> PackedInt64Array:
	_ensure_loaded()
	var key := str(app_id)
	if not _cache.has(key):
		return PackedInt64Array()
	var raw: Variant = _cache[key]
	var out := PackedInt64Array()
	if raw is Array:
		for entry in raw:
			var id := int(entry)
			if id > 0 and not is_removed(app_id, id):
				out.append(id)
	return out


static func is_removed(app_id: int, file_id: int) -> bool:
	if app_id <= 0 or file_id <= 0:
		return false
	_ensure_loaded()
	var removed: Variant = _cache.get(REMOVED_KEY, {})
	if removed is Dictionary:
		var list: Variant = removed.get(str(app_id), [])
		if list is Array:
			return list.has(file_id)
	return false


static func mark_removed(app_id: int, file_id: int) -> void:
	remove(app_id, file_id)
	if app_id <= 0 or file_id <= 0:
		return
	_ensure_loaded()
	var removed: Dictionary = {}
	if _cache.get(REMOVED_KEY, {}) is Dictionary:
		removed = _cache[REMOVED_KEY] as Dictionary
	var key := str(app_id)
	var ids: Array = []
	if removed.has(key) and removed[key] is Array:
		ids = (removed[key] as Array).duplicate()
	if not ids.has(file_id):
		ids.append(file_id)
	removed[key] = ids
	_cache[REMOVED_KEY] = removed
	_persist()


static func add(app_id: int, file_id: int) -> void:
	if app_id <= 0 or file_id <= 0:
		return
	if is_removed(app_id, file_id):
		return
	_ensure_loaded()
	var key := str(app_id)
	var ids: Array = []
	if _cache.has(key) and _cache[key] is Array:
		ids = (_cache[key] as Array).duplicate()
	if not ids.has(file_id):
		ids.append(file_id)
	_cache[key] = ids
	_persist()


static func remove(app_id: int, file_id: int) -> void:
	if app_id <= 0 or file_id <= 0:
		return
	_ensure_loaded()
	var key := str(app_id)
	if not _cache.has(key):
		return
	var ids: Array = _cache[key] if _cache[key] is Array else []
	ids.erase(file_id)
	if ids.is_empty():
		_cache.erase(key)
	else:
		_cache[key] = ids
	_persist()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		_cache = {}
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_cache = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_cache = parsed
	else:
		_cache = {}


static func _persist() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		AppLogger.error("Could not save UGC registry: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_cache, "\t"))
