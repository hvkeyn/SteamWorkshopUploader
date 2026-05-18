extends Button

var upload_target_path: String = ""

var _dialog: FileDialog


signal target_path_changed(path: String)


func _ready() -> void:
	disabled = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_pressed() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
		_dialog = null

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.title = "Select folder to upload"
	_dialog.use_native_dialog = UserPreferences.fetch().native_dialogs

	var start_dir := upload_target_path
	if start_dir.is_empty():
		start_dir = UserPreferences.fetch().last_browse_dir
	if not start_dir.is_empty() and DirAccess.dir_exists_absolute(start_dir):
		_dialog.current_dir = start_dir

	_dialog.dir_selected.connect(_on_dir_selected)
	_dialog.canceled.connect(_on_dialog_closed)
	_dialog.close_requested.connect(_on_dialog_closed)

	add_child(_dialog)
	_dialog.popup_centered_ratio(0.8)


func _on_dir_selected(path: String) -> void:
	AppLogger.info("Got target folder: " + path)
	upload_target_path = path
	target_path_changed.emit(upload_target_path)
	UserPreferences.fetch().last_browse_dir = path
	_close_dialog()


func _on_dialog_closed() -> void:
	_close_dialog()


func _close_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _exit_tree() -> void:
	_close_dialog()
