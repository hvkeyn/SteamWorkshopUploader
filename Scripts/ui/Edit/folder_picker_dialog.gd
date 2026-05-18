class_name FolderPickerDialog
extends AcceptDialog

## Folder picker with pasteable path field (always shown in this dialog).

const PathUtils = preload("res://Scripts/path_input_utils.gd")

signal folder_selected(path: String)

var _path_edit: LineEdit
var _browse_dialog: FileDialog


func _init() -> void:
	title = "Select folder to upload"
	ok_button_text = "Select folder"
	cancel_button_text = "Cancel"
	min_size = Vector2i(560, 140)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var hint := Label.new()
	hint.text = "Paste a full folder path or browse:"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.placeholder_text = "E:/Games/MyMod  or  E:\\Games\\MyMod"
	_path_edit.text_submitted.connect(_navigate_to_typed_path)
	vbox.add_child(_path_edit)

	var browse_btn := Button.new()
	browse_btn.text = "Browse folders…"
	browse_btn.pressed.connect(_open_browse_dialog)
	vbox.add_child(browse_btn)

	confirmed.connect(_on_confirmed)
	canceled.connect(_on_cancelled)


func open_picker(start_dir: String = "") -> void:
	var dir := PathUtils.normalize_directory_path(start_dir)
	if PathUtils.is_existing_directory(dir):
		_path_edit.text = dir
		_path_edit.caret_column = _path_edit.text.length()
	popup_centered()


func _navigate_to_typed_path(_text: String = "") -> void:
	var path := PathUtils.normalize_directory_path(_path_edit.text)
	if path.is_empty():
		AppLogger.error("Folder path is empty.")
		return
	if not PathUtils.is_existing_directory(path):
		AppLogger.error("Folder not found: " + path)
		return
	_path_edit.text = path
	_open_browse_dialog(path)


func _open_browse_dialog(start_dir: String = "") -> void:
	if _browse_dialog == null:
		_browse_dialog = FileDialog.new()
		_browse_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_browse_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_browse_dialog.use_native_dialog = false
		_browse_dialog.dir_selected.connect(_on_browse_dir_selected)
		add_child(_browse_dialog)

	var dir := PathUtils.normalize_directory_path(start_dir)
	if dir.is_empty():
		dir = PathUtils.normalize_directory_path(_path_edit.text)
	if PathUtils.is_existing_directory(dir):
		_browse_dialog.current_dir = dir
	_browse_dialog.popup_centered_ratio(0.75)


func _on_browse_dir_selected(path: String) -> void:
	var dir := PathUtils.normalize_directory_path(path)
	_path_edit.text = dir
	_path_edit.grab_focus()


func _on_confirmed() -> void:
	var path := PathUtils.normalize_directory_path(_path_edit.text)
	if not PathUtils.is_existing_directory(path):
		AppLogger.error("Folder not found: " + path)
		return
	folder_selected.emit(path)
	hide()


func _on_cancelled() -> void:
	hide()
