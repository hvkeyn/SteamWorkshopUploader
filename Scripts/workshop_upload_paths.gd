extends RefCounted

const MAX_PREVIEW_BYTES := 1024 * 1024


static func to_steam_path(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return ""
	normalized = normalized.simplify_path()
	if OS.get_name() == "Windows":
		return normalized.replace("/", "\\")
	return normalized


## Paths passed into GodotSteam / Steam API (forward slashes on Windows).
static func to_steam_api_path(path: String) -> String:
	return to_steam_path(path).replace("\\", "/")


## Path for SetItemContent / SetItemPreview (plain backslashes; do not use \\?\ prefix).
static func to_steam_native_api_path(path: String) -> String:
	return to_steam_path(path)


static func staging_parent_for_source(_source_dir: String) -> String:
	if OS.get_name() == "Windows":
		var local_app_data := OS.get_environment("LOCALAPPDATA").strip_edges()
		if not local_app_data.is_empty():
			return to_steam_path(local_app_data.path_join("SteamWorkshopUploader_staging"))
	return OS.get_temp_dir()


## Paths for GodotSteam on Windows: backslashes (forward slashes often fail at submit).
static func to_steam_upload_path(path: String) -> String:
	return to_steam_native_api_path(path)


static func probe_staged_folder(staged_dir: String) -> String:
	var native := to_steam_path(staged_dir)
	var largest_path := ""
	var largest_size := 0
	var pending: Array[String] = [native]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var access := DirAccess.open(current)
		if access == null:
			continue
		access.list_dir_begin()
		var entry := access.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full := current.path_join(entry)
				if access.current_is_dir():
					pending.append(full)
				else:
					var file := FileAccess.open(full, FileAccess.READ)
					if file != null:
						var sz := file.get_length()
						file.close()
						if sz > largest_size:
							largest_size = sz
							largest_path = full
			entry = access.get_next()
		access.list_dir_end()
	if largest_path.is_empty():
		return "Staging probe: no readable files found."
	return "Staging probe: largest file %s (%.1f MB)." % [
		largest_path,
		float(largest_size) / (1024.0 * 1024.0),
	]


static func count_files_recursive(dir_path: String) -> int:
	var native_dir := to_steam_path(dir_path)
	if not DirAccess.dir_exists_absolute(native_dir):
		return -1

	var total := 0
	var pending: Array[String] = [native_dir]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var access := DirAccess.open(current)
		if access == null:
			continue
		access.list_dir_begin()
		var entry := access.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full := current.path_join(entry)
				if access.current_is_dir():
					pending.append(full)
				else:
					total += 1
			entry = access.get_next()
		access.list_dir_end()
	return total


## True when the path lives under a Steam library (steamapps/common/…).
## The Steam client often returns RESULT_FILE_NOT_FOUND for UGC uploads from there.
static func is_steam_library_path(path: String) -> bool:
	var lower := to_steam_path(path).to_lower().replace("/", "\\")
	return "\\steamapps\\" in lower


static func is_inside_folder(file_path: String, folder_path: String) -> bool:
	var file_native := to_steam_path(file_path).to_lower()
	var folder_native := to_steam_path(folder_path).to_lower()
	if not folder_native.ends_with("\\"):
		folder_native += "\\"
	return file_native.begins_with(folder_native)


static func validate_content_folder(path: String) -> String:
	if path.is_empty():
		return "No content folder selected. Choose a folder on the Files tab."
	var native := to_steam_path(path)
	if not DirAccess.dir_exists_absolute(native):
		return "Content folder does not exist:\n%s" % native
	var file_count := count_files_recursive(native)
	if file_count < 0:
		return "Cannot read content folder:\n%s" % native
	if file_count == 0:
		return "Content folder is empty (0 files):\n%s" % native
	return ""


static func folder_size_bytes(dir_path: String) -> int:
	var total := 0
	var native := to_steam_path(dir_path)
	if not DirAccess.dir_exists_absolute(native):
		return 0
	var pending: Array[String] = [native]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var access := DirAccess.open(current)
		if access == null:
			continue
		access.list_dir_begin()
		var entry := access.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full := current.path_join(entry)
				if access.current_is_dir():
					pending.append(full)
				else:
					var file := FileAccess.open(full, FileAccess.READ)
					if file != null:
						total += file.get_length()
						file.close()
			entry = access.get_next()
		access.list_dir_end()
	return total


static func warn_if_game_install_folder(path: String) -> String:
	var native := to_steam_path(path)
	var access := DirAccess.open(native)
	if access == null:
		return ""
	access.list_dir_begin()
	var entry := access.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if not access.current_is_dir() and entry.to_lower().ends_with(".exe"):
				access.list_dir_end()
				return (
					"Похоже, выбрана папка установки игры, а не пакет мода.\n"
					+ "Укажите папку с файлами перевода (например COPY_TO_GAME_FOLDER), а не корень TurretGirls."
				)
		entry = access.get_next()
	access.list_dir_end()
	return ""


static func max_path_length_in_tree(dir_path: String) -> int:
	var native := to_steam_path(dir_path)
	if not DirAccess.dir_exists_absolute(native):
		return 0
	var longest := native.length()
	var pending: Array[String] = [native]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var access := DirAccess.open(current)
		if access == null:
			continue
		access.list_dir_begin()
		var entry := access.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full := current.path_join(entry)
				longest = maxi(longest, full.length())
				if access.current_is_dir():
					pending.append(full)
			entry = access.get_next()
		access.list_dir_end()
	return longest


static func validate_staged_against_source(source_dir: String, staged_dir: String) -> String:
	var src_count := count_files_recursive(source_dir)
	var staged_count := count_files_recursive(staged_dir)
	if src_count < 0 or staged_count < 0:
		return "Cannot verify staged files after copy."
	if staged_count != src_count:
		return (
			"Staging incomplete: expected %d files, found %d in temp."
			% [src_count, staged_count]
		)
	var src_bytes := folder_size_bytes(source_dir)
	var staged_bytes := folder_size_bytes(staged_dir)
	if src_bytes > 0 and staged_bytes < int(float(src_bytes) * 0.99):
		return (
			"Staging size mismatch: source %.1f MB, temp %.1f MB."
			% [float(src_bytes) / (1024.0 * 1024.0), float(staged_bytes) / (1024.0 * 1024.0)]
		)
	var max_len := max_path_length_in_tree(staged_dir)
	if OS.get_name() == "Windows" and max_len > 240:
		return (
			"Some file paths exceed %d characters (max %d). "
			+ "Move the mod to a shorter path such as D:\\Mods\\TG_RU\\."
			% [240, max_len]
		)
	return ""


static func stage_content_for_steam(source_dir: String) -> Dictionary:
	var native := to_steam_path(source_dir)
	var empty: Dictionary = {"path": native, "is_temp": false, "temp_root": "", "log": ""}
	if native.is_empty():
		return empty

	var file_count := count_files_recursive(native)
	if file_count < 0:
		return {
			"path": native,
			"is_temp": false,
			"temp_root": "",
			"log": "",
			"error": "Cannot read content folder:\n%s" % native,
		}

	var pre_copy_log := ""
	if is_steam_library_path(native):
		var size_mb := float(folder_size_bytes(native)) / (1024.0 * 1024.0)
		pre_copy_log = (
			"Source is inside steamapps — copying %.1f MB to %s …"
			% [size_mb, staging_parent_for_source(native)]
		)
	elif native.contains("SteamWorkshopUploader_staging") or native.contains("steamworkshop_temp_"):
		return {
			"path": native,
			"is_temp": false,
			"temp_root": "",
			"log": "Using prepared upload folder (%d files): %s" % [file_count, native],
		}
	elif _can_upload_content_directly(native):
		return {
			"path": native,
			"is_temp": false,
			"temp_root": "",
			"log": (
				"Using source folder directly for Steam (%d files, no extra copy): %s"
				% [file_count, native]
			),
		}

	var stage_t0_ms := Time.get_ticks_msec()
	var staging_parent := staging_parent_for_source(native) if is_steam_library_path(native) else ""
	var mirrored: Dictionary = TempFolder.mirror_directory_to_temp(native, staging_parent)
	if mirrored.is_empty():
		return {
			"path": native,
			"is_temp": false,
			"temp_root": "",
			"log": "",
			"error": (
				"Could not copy workshop files to a temporary folder.\n"
				+ "Try moving your mod outside the Steam library (e.g. D:\\Mods\\MyMod)."
			),
		}

	var temp_root := to_steam_path(str(mirrored.get("temp_root", "")))
	var content_dir := to_steam_path(str(mirrored.get("content_dir", "")))

	var verify_error := validate_staged_against_source(native, content_dir)
	if verify_error != "":
		TempFolder.remove_temp_path(temp_root)
		return {
			"path": native,
			"is_temp": false,
			"temp_root": "",
			"log": "",
			"error": verify_error,
		}

	var stage_sec := float(Time.get_ticks_msec() - stage_t0_ms) / 1000.0
	var log_lines: PackedStringArray = PackedStringArray()
	if pre_copy_log != "":
		log_lines.append(pre_copy_log)
	var robocopy_code := int(mirrored.get("robocopy_code", -1))
	if robocopy_code >= 0:
		log_lines.append("Robocopy exit code: %d (0–7 = OK)." % robocopy_code)
	log_lines.append(
		"Copied %d files to temporary staging in %.1f s: %s"
		% [file_count, stage_sec, content_dir]
	)
	log_lines.append(probe_staged_folder(content_dir))

	return {
		"path": content_dir,
		"temp_root": temp_root,
		"is_temp": true,
		"log": "\n".join(log_lines),
	}


static func _can_upload_content_directly(native_folder: String) -> bool:
	if native_folder.is_empty() or not DirAccess.dir_exists_absolute(native_folder):
		return false
	if warn_if_game_install_folder(native_folder) != "":
		return false
	if count_files_recursive(native_folder) <= 0:
		return false
	# Heuristic: only skip temp staging on local drives (E:\, D:\, C:\…).
	if OS.get_name() == "Windows":
		var drive := native_folder.substr(0, 3)
		if drive.length() >= 2 and drive[1] == ":":
			return true
	return native_folder.begins_with("/")


static func validate_preview_file(path: String) -> String:
	if path.is_empty():
		return "No preview image selected."
	var native := to_steam_path(path)
	if not FileAccess.file_exists(native):
		return "Preview image not found:\n%s" % native
	var size: int = FileAccess.get_file_as_bytes(native).size()
	if size <= 0:
		return "Preview image is empty:\n%s" % native
	if size > MAX_PREVIEW_BYTES:
		return (
			"Preview image is %.1f MB (Steam maximum is 1 MB):\n%s"
			% [float(size) / (1024.0 * 1024.0), native]
		)
	var image := Image.new()
	if image.load(native) != OK:
		return "Preview is not a valid image (use JPG or PNG):\n%s" % native
	return ""
