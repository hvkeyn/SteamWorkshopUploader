extends Button

var upload_target_path: String = ""

var _picker: FolderPickerDialog


signal target_path_changed(path: String)


func _on_pressed() -> void:
	if _picker == null:
		_picker = FolderPickerDialog.new()
		_picker.folder_selected.connect(_on_folder_selected)
		get_tree().root.add_child(_picker)

	var start_dir := upload_target_path
	if start_dir.is_empty():
		start_dir = UserPreferences.fetch().last_browse_dir
	_picker.open_picker(start_dir)


func _on_folder_selected(path: String) -> void:
	AppLogger.info("Got target folder: " + path)
	upload_target_path = path
	target_path_changed.emit(upload_target_path)
	UserPreferences.fetch().last_browse_dir = path


func _exit_tree() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
