extends Button

const FILTERS = [
	"*.png,*.jpg,*.jpeg;Image Files;image/png,image/jpeg",
	"*.gif;Animated Image Files;image/gif"
]

var preview_image_path: String = ""

var _dialog: FileDialog

signal preview_changed(path: String)


func _on_pressed() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = FILTERS
	_dialog.use_native_dialog = UserPreferences.fetch().native_dialogs

	if UserPreferences.fetch().last_browse_dir != "":
		_dialog.current_dir = UserPreferences.fetch().last_browse_dir

	_dialog.file_selected.connect(on_file_selected)
	_dialog.canceled.connect(_close_dialog)
	_dialog.close_requested.connect(_close_dialog)

	var host := get_window()
	if host:
		host.add_child(_dialog)
	else:
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.8)


func _close_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null

func on_file_selected(path:String) -> void:
	AppLogger.info("Got preview file: " + path)
	preview_image_path = path
	WebImage.load_from_path(preview_image_path, %SpritePreviewImage)
	
	var byte_size = WebImage.get_byte_size_from_path(preview_image_path)
	AppLogger.info("Preview image size is " + str(byte_size) + " bytes")

	UserPreferences.fetch().last_browse_dir = _dialog.current_dir

	if byte_size > 1024 * 1024:
		AppLogger.warning("Preview image is larger than 1MB! This may cause issues with uploading.")

	preview_changed.emit(preview_image_path)
	_close_dialog()


func _exit_tree() -> void:
	_close_dialog()
