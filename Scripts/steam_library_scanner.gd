class_name SteamLibraryScanner
extends RefCounted

## Reads the signed-in Steam account library from local Steam client files.

const Vdf = preload("res://Scripts/steam_vdf.gd")
const MasterList = preload("res://Scripts/steam_master_app_list.gd")

const STEAM_ID64_BASE := 76561197960265728
const NAME_CACHE_PATH := "user://steam_app_names.json"

# Tools / redistributables that are not useful for Workshop uploads.
const EXCLUDED_APP_IDS: Array[int] = [
	7,       # Steam client
	228980,  # Steamworks Common Redistributables
	229020,  # Steamworks Common Redistributables
	1070560, # Steam Linux Runtime
	1391110, # Steam Linux Runtime
	1628350, # Steam Linux Runtime
]


static func discover() -> Dictionary:
	var steam_path := find_steam_path()
	if steam_path.is_empty():
		return {"ok": false, "error": "Steam installation not found.", "apps": []}

	var account_id := find_account_id(steam_path)
	if account_id.is_empty():
		return {"ok": false, "error": "No Steam user found in loginusers.vdf.", "apps": []}

	var app_ids := collect_owned_app_ids(steam_path, account_id)
	if app_ids.is_empty():
		return {"ok": false, "error": "No games found in Steam library config.", "apps": []}

	MasterList.ensure_loaded()

	var names := load_name_cache()
	names.merge(collect_manifest_names(steam_path), true)

	var apps: Array[Dictionary] = []
	var missing_names: Array[int] = []

	for app_id in app_ids:
		var name: String = str(names.get(str(app_id), ""))
		if name.is_empty():
			name = MasterList.lookup_app_name(app_id)
		if name.is_empty():
			name = "App %d" % app_id
			missing_names.append(app_id)
		apps.append({"app_id": app_id, "name": name})

	apps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["name"].nocasecmp_to(b["name"]) < 0
	)

	return {
		"ok": true,
		"error": "",
		"apps": apps,
		"missing_names": missing_names,
		"steam_path": steam_path,
	}


static func find_steam_path() -> String:
	var env_path := OS.get_environment("STEAM_PATH").strip_edges()
	if not env_path.is_empty() and _is_steam_dir(env_path):
		return _normalize_path(env_path)

	if OS.get_name() == "Windows":
		var output: PackedStringArray = []
		var exit_code := OS.execute(
			"reg",
			["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"],
			output,
			true,
			false
		)
		if exit_code == 0:
			for line in output:
				if "SteamPath" in line and "REG_SZ" in line:
					var parts := line.split("REG_SZ", false, 1)
					if parts.size() == 2:
						var path := parts[1].strip_edges()
						if _is_steam_dir(path):
							return _normalize_path(path)

	var candidates: Array[String] = [
		"C:/Program Files (x86)/Steam",
		"C:/Program Files/Steam",
		"D:/Steam",
	]
	if OS.get_name() == "Linux":
		var home := OS.get_environment("HOME")
		candidates = [
			home + "/.steam/steam",
			home + "/.local/share/Steam",
		]
	elif OS.get_name() == "macOS":
		var home := OS.get_environment("HOME")
		candidates = [home + "/Library/Application Support/Steam"]

	for path in candidates:
		if _is_steam_dir(path):
			return _normalize_path(path)

	return ""


static func find_account_id(steam_path: String) -> String:
	var login_path := steam_path.path_join("config/loginusers.vdf")
	var data: Dictionary = Vdf.parse_file(login_path)
	var users: Variant = data.get("users", {})
	if not users is Dictionary:
		return ""

	var fallback_id := ""
	for steam_id in users.keys():
		var entry: Variant = users[steam_id]
		if not entry is Dictionary:
			continue
		var account_id := steam_id64_to_account_id(str(steam_id))
		if account_id.is_empty():
			continue
		fallback_id = account_id
		if str(entry.get("MostRecent", "0")) == "1":
			return account_id

	return fallback_id


static func steam_id64_to_account_id(steam_id64: String) -> String:
	if not steam_id64.is_valid_int():
		return ""
	var id := int(steam_id64)
	if id <= STEAM_ID64_BASE:
		return ""
	return str(id - STEAM_ID64_BASE)


static func collect_owned_app_ids(steam_path: String, account_id: String) -> Array[int]:
	var config_path := steam_path.path_join("userdata/%s/config/localconfig.vdf" % account_id)
	return _collect_app_ids_from_localconfig(config_path)


static func _collect_app_ids_from_localconfig(config_path: String) -> Array[int]:
	if not FileAccess.file_exists(config_path):
		return []

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return []

	var in_steam_section := false
	var in_apps_section := false
	var apps_brace_depth := 0
	var ids: Array[int] = []

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue

		if line == '"Steam"':
			in_steam_section = true
			in_apps_section = false
			continue

		if not in_steam_section:
			continue

		if line == '"apps"':
			in_apps_section = true
			apps_brace_depth = 0
			continue

		if not in_apps_section:
			continue

		if line == "{":
			apps_brace_depth += 1
			continue

		if line == "}":
			apps_brace_depth -= 1
			if apps_brace_depth <= 0:
				in_apps_section = false
				in_steam_section = false
			continue

		if apps_brace_depth != 1:
			continue

		if not line.begins_with("\""):
			continue

		var key := line.trim_prefix("\"").trim_suffix("\"")
		if not key.is_valid_int():
			continue

		var app_id := int(key)
		if app_id <= 0 or app_id in EXCLUDED_APP_IDS:
			continue
		ids.append(app_id)

	return ids


static func collect_manifest_names(steam_path: String) -> Dictionary:
	var names: Dictionary = {}
	for library_path in collect_library_paths(steam_path):
		var steamapps_dir := library_path.path_join("steamapps")
		if not DirAccess.dir_exists_absolute(steamapps_dir):
			continue
		var dir := DirAccess.open(steamapps_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.begins_with("appmanifest_") and file_name.ends_with(".acf"):
				var manifest: Dictionary = Vdf.parse_file(steamapps_dir.path_join(file_name))
				var state: Variant = manifest.get("AppState", {})
				if state is Dictionary:
					var app_id_str := str(state.get("appid", ""))
					var app_name := str(state.get("name", ""))
					if app_id_str.is_valid_int() and not app_name.is_empty():
						names[app_id_str] = app_name
			file_name = dir.get_next()
		dir.list_dir_end()
	return names


static func collect_library_paths(steam_path: String) -> Array[String]:
	var paths: Array[String] = [_normalize_path(steam_path)]
	var library_file := steam_path.path_join("config/libraryfolders.vdf")
	var data: Dictionary = Vdf.parse_file(library_file)
	var libraries: Variant = data.get("libraryfolders", {})
	if not libraries is Dictionary:
		return paths

	for key in libraries.keys():
		var entry: Variant = libraries[key]
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", "")).strip_edges()
		if path.is_empty():
			continue
		path = _normalize_path(path)
		if path not in paths:
			paths.append(path)
	return paths


static func load_name_cache() -> Dictionary:
	if not FileAccess.file_exists(NAME_CACHE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(NAME_CACHE_PATH)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


static func save_name_cache(cache: Dictionary) -> void:
	var file := FileAccess.open(NAME_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(cache))


static func get_local_icon(app_id: int) -> Texture2D:
	for ext in ["jpg", "png"]:
		var path := "res://assets/textures/steamapps/%d.%s" % [app_id, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


static func _is_steam_dir(path: String) -> bool:
	var normalized := _normalize_path(path)
	return DirAccess.dir_exists_absolute(normalized) and FileAccess.file_exists(normalized.path_join("steam.exe"))


static func _normalize_path(path: String) -> String:
	return path.replace("\\", "/").rstrip("/")
