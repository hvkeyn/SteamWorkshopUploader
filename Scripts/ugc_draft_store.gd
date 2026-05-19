extends RefCounted

## Persists per–workshop-item editor drafts between app restarts (user://).

const SAVE_PATH := "user://ugc_item_drafts.json"

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func get_draft(file_id: int) -> Dictionary:
	_ensure_loaded()
	var key := str(file_id)
	if _cache.has(key) and _cache[key] is Dictionary:
		return (_cache[key] as Dictionary).duplicate(true)
	return {}


static func set_draft(file_id: int, draft: Dictionary) -> void:
	if file_id <= 0:
		return
	_ensure_loaded()
	var key := str(file_id)
	if _is_effectively_empty(draft) and _cache.has(key) and _cache[key] is Dictionary:
		if not _is_effectively_empty(_cache[key]):
			return
	_cache[key] = draft.duplicate(true)
	_persist()


static func _is_effectively_empty(draft: Dictionary) -> bool:
	if draft.is_empty():
		return true
	if str(draft.get("title", "")).strip_edges() != "":
		return false
	if str(draft.get("description", "")).strip_edges() != "":
		return false
	if str(draft.get("change_notes", "")).strip_edges() != "":
		return false
	if str(draft.get("preview_path", "")).strip_edges() != "":
		return false
	if str(draft.get("upload_path", "")).strip_edges() != "":
		return false
	var tags: Variant = draft.get("tags", [])
	if tags is Array and not tags.is_empty():
		return false
	return true


static func get_all_file_ids() -> Array:
	_ensure_loaded()
	var ids: Array = []
	for key in _cache.keys():
		var file_id := int(key)
		if file_id > 0:
			ids.append(file_id)
	return ids


## Drafts created for a specific game (avoids showing items from another AppID after switching).
static func get_file_ids_for_app(app_id: int) -> Array:
	if app_id <= 0:
		return []
	_ensure_loaded()
	const UgcItemRegistry = preload("res://Scripts/ugc_item_registry.gd")
	var ids: Array = []
	for key in _cache.keys():
		var file_id := int(key)
		if file_id <= 0:
			continue
		var draft: Dictionary = {}
		if _cache[key] is Dictionary:
			draft = _cache[key] as Dictionary
		var draft_app := int(draft.get("app_id", 0))
		if draft_app > 0:
			if draft_app == app_id:
				ids.append(file_id)
		elif UgcItemRegistry.get_ids_for_app(app_id).has(file_id):
			ids.append(file_id)
	return ids


static func erase_draft(file_id: int) -> void:
	if file_id <= 0:
		return
	_ensure_loaded()
	if not _cache.erase(str(file_id)):
		return
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
		AppLogger.error("Could not load UGC drafts: " + str(FileAccess.get_open_error()))
		_cache = {}
		return
	var text := file.get_as_text()
	if text.is_empty():
		_cache = {}
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_cache = parsed
	else:
		_cache = {}
		AppLogger.warning("UGC drafts file was invalid; starting fresh.")


static func _persist() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		AppLogger.error("Could not save UGC drafts: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_cache, "\t"))
