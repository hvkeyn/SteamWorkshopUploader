class_name TempFolder

static func create_temp_folder(parent_dir: String = "") -> String:
	var base_dir := parent_dir.strip_edges()
	if base_dir.is_empty():
		base_dir = OS.get_temp_dir()
	else:
		base_dir = base_dir.simplify_path()
		DirAccess.make_dir_recursive_absolute(base_dir)
	# Second-resolution timestamps collide when content + preview stage in one frame.
	var folder_name := "steamworkshop_temp_%d_%d" % [
		Time.get_unix_time_from_system(),
		Time.get_ticks_usec(),
	]
	var temp_path := base_dir.path_join(folder_name)

	var dir := DirAccess.open(base_dir)
	if dir == null:
		AppLogger.error("Cannot open staging directory: " + base_dir)
		return ""

	var err := dir.make_dir(folder_name)
	if err == ERR_ALREADY_EXISTS:
		folder_name = "steamworkshop_temp_%d_%d_%d" % [
			Time.get_unix_time_from_system(),
			Time.get_ticks_usec(),
			randi() % 100000,
		]
		temp_path = base_dir.path_join(folder_name)
		err = dir.make_dir(folder_name)

	if err != OK:
		AppLogger.error("Failed to create temporary directory: " + temp_path)
		return ""

	return temp_path

## Copy each of the provided absolute file paths to the corresponding relative paths, relative to target_path.
static func copy_files_to_folder(target_path:String, absolute_paths:Array[String], relative_paths:Array[String]) -> bool:
	if absolute_paths.size() != relative_paths.size():
		AppLogger.error("Mismatched array sizes in copy_files_to_folder")
		return false
		
	var dir = DirAccess.open(target_path)
	if not dir:
		AppLogger.error("Could not open target directory: " + target_path)
		return false
		
	for i in range(absolute_paths.size()):
		var abs_path = absolute_paths[i]
		var rel_path = relative_paths[i]
		var final_path = (target_path + "/" + rel_path).simplify_path()
		
		# Create any needed subdirectories
		var rel_dir = rel_path.get_base_dir()
		if rel_dir != "":
			if dir.make_dir_recursive(rel_dir) != OK:
				AppLogger.error("Failed to create subdirectory: " + rel_dir)
				return false
				
		# Copy the file
		var err = DirAccess.copy_absolute(abs_path, final_path)
		if err != OK:
			AppLogger.error("Failed to copy file %s to %s: %d" % [abs_path, rel_path, err])
			return false
			
	return true


## Copies source_dir into a temp folder preserving the exact folder layout (for mod packages).
static func mirror_directory_to_temp(source_dir: String, parent_dir: String = "") -> Dictionary:
	var native_source := source_dir.simplify_path()
	if not DirAccess.dir_exists_absolute(native_source):
		AppLogger.error("Cannot stage content, folder not found: " + native_source)
		return {}

	var temp_root := create_temp_folder(parent_dir)
	if temp_root.is_empty():
		return {}

	var dest_dir := temp_root
	var copy_err := OK
	var robocopy_code := -1
	if OS.get_name() == "Windows":
		var robocopy_result: Dictionary = _mirror_with_robocopy(native_source, dest_dir)
		copy_err = robocopy_result.get("error", ERR_CANT_CREATE)
		robocopy_code = int(robocopy_result.get("exit_code", -1))
	if copy_err != OK:
		copy_err = _copy_dir_contents(native_source, dest_dir)
		robocopy_code = -1
	if copy_err != OK:
		remove_temp_path(temp_root)
		return {}

	return {"temp_root": temp_root, "content_dir": dest_dir, "robocopy_code": robocopy_code}


## Robocopy follows junctions and copies real file bytes (Godot copy can be too fast / incomplete).
static func _mirror_with_robocopy(src_dir: String, dst_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dst_dir)
	var output: PackedStringArray = []
	var exit_code: int = OS.execute(
		"robocopy",
		PackedStringArray([
			src_dir.replace("/", "\\"),
			dst_dir.replace("/", "\\"),
			"/E",
			"/COPY:DAT",
			"/XJ",
			"/R:2",
			"/W:1",
			"/NFL",
			"/NDL",
			"/NJH",
			"/NJS",
			"/NC",
			"/NS",
		]),
		output,
		true,
		false
	)
	# Robocopy: 0–7 = success (0 = nothing to copy).
	if exit_code >= 8:
		AppLogger.error("robocopy failed with exit code %d (%s -> %s)" % [exit_code, src_dir, dst_dir])
		return {"error": ERR_CANT_CREATE, "exit_code": exit_code}
	return {"error": OK, "exit_code": exit_code}


static func _copy_dir_contents(src_dir: String, dst_dir: String) -> Error:
	var access := DirAccess.open(src_dir)
	if access == null:
		AppLogger.error("Cannot read folder: " + src_dir)
		return ERR_CANT_OPEN

	access.list_dir_begin()
	var entry := access.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var from_path := src_dir.path_join(entry)
			var to_path := dst_dir.path_join(entry)
			if access.current_is_dir():
				DirAccess.make_dir_recursive_absolute(to_path)
				var sub_err := _copy_dir_contents(from_path, to_path)
				if sub_err != OK:
					access.list_dir_end()
					return sub_err
			else:
				var copy_err := DirAccess.copy_absolute(from_path, to_path)
				if copy_err != OK:
					AppLogger.error(
						"Failed to copy %s -> %s (error %d)" % [from_path, to_path, copy_err]
					)
					access.list_dir_end()
					return copy_err
		entry = access.get_next()
	access.list_dir_end()
	return OK


static func remove_temp_path(path: String) -> void:
	if path.is_empty() or not path.contains("steamworkshop_temp_"):
		return
	var dir := path
	if FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)
		dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return
	_remove_dir_recursive(dir)


static func _remove_dir_recursive(dir_path: String) -> void:
	var access := DirAccess.open(dir_path)
	if access == null:
		return
	access.list_dir_begin()
	var entry := access.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := dir_path.path_join(entry)
			if access.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = access.get_next()
	access.list_dir_end()
	DirAccess.remove_absolute(dir_path)
