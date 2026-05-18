class_name FolderPickerDialog
extends Window

## Folder picker with pasteable path (shown as a proper popup window).

const PathUtils = preload("res://Scripts/path_input_utils.gd")

signal folder_selected(path: String)

var _path_edit: LineEdit
var _browse_dialog: FileDialog
var _ui_built: bool = false


func _init() -> void:
	title = "Select folder to upload"
	size = Vector2i(640, 220)
	min_size = Vector2i(480, 180)
	unresizable = false
	exclusive = true
	close_requested.connect(_on_cancelled)


func popup_over(host: Window, start_dir: String = "") -> void:
	_ensure_ui()
	if get_parent() != host:
		if get_parent():
			get_parent().remove_child(self)
		host.add_child(self)
	var dir := PathUtils.normalize_directory_path(start_dir)
	if PathUtils.is_existing_directory(dir):
		_path_edit.text = dir
		_path_edit.caret_column = _path_edit.text.length()
	popup_centered()
	_path_edit.grab_focus()


func _ensure_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

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

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancelled)
	btn_row.add_child(cancel_btn)

	var ok_btn := Button.new()
	ok_btn.text = "Select folder"
	ok_btn.pressed.connect(_on_confirmed)
	btn_row.add_child(ok_btn)


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
		_browse_dialog.use_native_dialog = UserPreferences.fetch().native_dialogs
		_browse_dialog.dir_selected.connect(_on_browse_dir_selected)
		add_child(_browse_dialog)

	var dir := PathUtils.normalize_directory_path(start_dir)
	if dir.is_empty():
		dir = PathUtils.normalize_directory_path(_path_edit.text)
	if PathUtils.is_existing_directory(dir):
		_browse_dialog.current_dir = dir
	_browse_dialog.popup_centered_ratio(0.75)


func _on_browse_dir_selected(path: String) -> void:
	_path_edit.text = PathUtils.normalize_directory_path(path)
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
