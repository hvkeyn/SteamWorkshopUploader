extends RefCounted

const UploadPaths = preload("res://Scripts/workshop_upload_paths.gd")
const MAX_BYTES := 1024 * 1024


## Returns { path, is_temp, warning, created_new_dir } — path is safe for Steam.setItemPreview.
static func prepare_for_upload(source_path: String, staging_dir: String = "") -> Dictionary:
	var empty: Dictionary = {
		"path": source_path,
		"is_temp": false,
		"warning": "",
		"created_new_dir": false,
	}
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		empty["warning"] = "Preview file not found."
		return empty

	var native_source := UploadPaths.to_steam_path(source_path)
	var original_size: int = FileAccess.get_file_as_bytes(native_source).size()
	if original_size <= 0:
		empty["warning"] = "Preview file is empty."
		return empty

	var stage_parent := staging_dir.strip_edges()
	if stage_parent.is_empty():
		stage_parent = UploadPaths.staging_parent_for_source(native_source)
	var out_dir := TempFolder.create_temp_folder(stage_parent)
	var created_new_dir := not out_dir.is_empty()

	if out_dir.is_empty():
		empty["warning"] = "Could not create a temporary folder for the preview."
		return empty

	# Always re-encode preview as JPG in staging (Steam is picky about paths/formats).
	var out_path := UploadPaths.to_steam_path(out_dir.path_join("workshop_preview.jpg"))

	var image := Image.new()
	if image.load(native_source) != OK:
		empty["warning"] = "Preview could not be read as an image (use JPG or PNG)."
		return empty

	if original_size <= MAX_BYTES:
		var save_ok: Error = image.save_jpg(out_path, 0.92)
		if save_ok == OK and FileAccess.file_exists(out_path):
			return {
				"path": out_path,
				"is_temp": true,
				"warning": "Preview re-encoded for Steam upload.",
				"created_new_dir": created_new_dir,
			}

	var warning: String = "Preview was %.1f MB; compressed for Steam (max 1 MB)." % (
		float(original_size) / (1024.0 * 1024.0)
	)

	for scale in [0.85, 0.7, 0.55, 0.4, 0.3, 0.2]:
		var scaled: Image = image.duplicate()
		var w: int = maxi(1, int(image.get_width() * scale))
		var h: int = maxi(1, int(image.get_height() * scale))
		scaled.resize(w, h, Image.INTERPOLATE_LANCZOS)
		var save_err: Error = scaled.save_jpg(out_path, 0.88)
		if save_err != OK:
			continue
		var saved_size: int = FileAccess.get_file_as_bytes(out_path).size()
		if saved_size > 0 and saved_size <= MAX_BYTES:
			return {
				"path": out_path,
				"is_temp": true,
				"warning": warning,
				"created_new_dir": created_new_dir,
			}

	var tiny: Image = image.duplicate()
	tiny.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	tiny.save_jpg(out_path, 0.75)
	return {
		"path": out_path,
		"is_temp": true,
		"warning": warning,
		"created_new_dir": created_new_dir,
	}
