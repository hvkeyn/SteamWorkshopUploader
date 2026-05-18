extends VBoxContainer

signal tags_changed

var current_tags: Array = []

var _custom_tag_edit: LineEdit


func _ready() -> void:
	configure()


func configure() -> void:
	var tags_str := str(Steamworks.current_ugc_item.get("tags", ""))
	current_tags = _parse_tags_csv(tags_str)
	_rebuild_ui()


func set_tags(tags: Array) -> void:
	current_tags = []
	for entry in tags:
		var tag := str(entry).strip_edges()
		if not tag.is_empty() and not current_tags.has(tag):
			current_tags.append(tag)
	_rebuild_ui()


func _parse_tags_csv(tags_str: String) -> Array:
	var parsed: Array = []
	for part in tags_str.split(","):
		var tag := str(part).strip_edges()
		if not tag.is_empty() and not parsed.has(tag):
			parsed.append(tag)
	return parsed


func _collect_available_tags() -> Array:
	var available: Dictionary = {}
	if Steamworks.current_steam_app:
		for tag in Steamworks.current_steam_app.tags:
			var name := str(tag).strip_edges()
			if not name.is_empty():
				available[name] = true
	for tag in current_tags:
		available[str(tag)] = true
	return available.keys()


func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
	_custom_tag_edit = null

	for tag in _collect_available_tags():
		_add_tag_checkbox(str(tag))

	_ensure_custom_tag_row()
	_sync_checkboxes_to_current_tags()


func _ensure_custom_tag_row() -> void:
	if _custom_tag_edit != null and is_instance_valid(_custom_tag_edit):
		return

	var row := HBoxContainer.new()
	row.name = "CustomTagRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_custom_tag_edit = LineEdit.new()
	_custom_tag_edit.name = "CustomTagEdit"
	_custom_tag_edit.placeholder_text = "Add custom tag…"
	_custom_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_tag_edit.text_submitted.connect(_on_custom_tag_submitted)

	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_on_add_custom_tag_pressed)

	row.add_child(_custom_tag_edit)
	row.add_child(add_btn)
	add_child(row)


func _add_tag_checkbox(tag: String) -> void:
	for child in get_children():
		if child is CheckBox and child.text == tag:
			return

	var tag_item := CheckBox.new()
	tag_item.text = tag
	tag_item.button_pressed = current_tags.has(tag)
	tag_item.toggled.connect(on_tag_toggled.bind(tag))
	add_child(tag_item)


func _sync_checkboxes_to_current_tags() -> void:
	for child in get_children():
		if child is CheckBox:
			child.button_pressed = current_tags.has(child.text)


func _on_add_custom_tag_pressed() -> void:
	_on_custom_tag_submitted(_custom_tag_edit.text)


func _on_custom_tag_submitted(text: String) -> void:
	var tag := text.strip_edges()
	if tag.is_empty():
		return

	var had_checkbox := false
	for child in get_children():
		if child is CheckBox and child.text == tag:
			had_checkbox = true
			child.button_pressed = true
			break

	if not had_checkbox:
		_add_tag_checkbox(tag)

	if not current_tags.has(tag):
		current_tags.append(tag)

	if _custom_tag_edit:
		_custom_tag_edit.text = ""

	AppLogger.info("Tag list is now " + str(current_tags))
	tags_changed.emit()


func on_tag_toggled(toggled_on: bool, tag: String) -> void:
	if toggled_on:
		if not current_tags.has(tag):
			current_tags.append(tag)
	else:
		current_tags.erase(tag)
	AppLogger.info("Tag list is now " + str(current_tags))
	tags_changed.emit()
