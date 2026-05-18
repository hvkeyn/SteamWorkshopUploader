class_name SteamMasterAppList
extends RefCounted

## Offline lookup: Steam AppID -> game name (from SteamCMD-AppID-List CSV).

const CACHE_PATH := "user://steam_master_app_names.json"
const REMOTE_CSV_URL := "https://raw.githubusercontent.com/dgibbs64/SteamCMD-AppID-List/master/steamcmd_appid.csv"
const CACHE_MAX_AGE_SEC := 7 * 24 * 3600
const MIN_VALID_ENTRIES := 1000

static var _lookup: Dictionary = {}
static var _loaded: bool = false


static func get_lookup() -> Dictionary:
	ensure_loaded()
	return _lookup


## Object.get_name() shadows this; always call lookup_app_name(), not get_name().
static func lookup_app_name(app_id: int) -> String:
	ensure_loaded()
	return str(_lookup.get(str(app_id), ""))


static func get_display_name(app_id: int, fallback: String = "") -> String:
	var name := lookup_app_name(app_id)
	if not name.is_empty():
		return name
	return fallback


static func ensure_loaded() -> bool:
	if _loaded:
		return not _lookup.is_empty()
	_lookup = _load_cache_file()
	_loaded = true
	# Drop corrupted empty cache from a failed download.
	if _lookup.size() < MIN_VALID_ENTRIES:
		_lookup = {}
	return not _lookup.is_empty()


static func is_cache_stale() -> bool:
	if not FileAccess.file_exists(CACHE_PATH):
		return true
	var modified := FileAccess.get_modified_time(CACHE_PATH)
	return Time.get_unix_time_from_system() - modified > CACHE_MAX_AGE_SEC


static func apply_remote_csv(csv_text: String) -> int:
	if csv_text.length() < 100:
		return 0

	var lookup: Dictionary = {}
	for line in csv_text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		# Format: 5,"Dedicated Server"  or  730,Counter-Strike
		var comma := trimmed.find(",")
		if comma <= 0:
			continue
		var app_id_str := trimmed.substr(0, comma).strip_edges()
		var name_part := trimmed.substr(comma + 1).strip_edges()
		if name_part.begins_with("\"") and name_part.ends_with("\""):
			name_part = name_part.substr(1, name_part.length() - 2)
		if app_id_str.is_valid_int() and not name_part.is_empty():
			lookup[app_id_str] = name_part

	if lookup.size() < MIN_VALID_ENTRIES:
		AppLogger.error("Steam app name database parse failed (only %d entries)." % lookup.size())
		return 0

	_lookup = lookup
	_loaded = true
	_save_cache_file(lookup)
	return lookup.size()


static func _load_cache_file() -> Dictionary:
	if not FileAccess.file_exists(CACHE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(CACHE_PATH)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


static func _save_cache_file(lookup: Dictionary) -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(lookup))
