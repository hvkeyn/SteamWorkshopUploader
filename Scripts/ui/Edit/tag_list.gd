extends VBoxContainer

signal tags_changed

var current_tags: Array = []


func _ready() -> void:
	configure()


func configure() -> void:
	var item: Dictionary = Steamworks.current_ugc_item
	var tags_str := str(item.get("tags", ""))
	current_tags = _parse_tags_csv(tags_str)

	var file_id: int = int(item.get("file_id", -1))
	if file_id > 0 and Steamworks.ugc_items.has(file_id):
		var cached: Dictionary = Steamworks.ugc_items[file_id]
		for t in _parse_tags_csv(str(cached.get("tags", ""))):
			if not current_tags.has(t):
				current_tags.append(t)

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
	var available: Array = []
	if Steamworks.current_steam_app:
		for tag in Steamworks.current_steam_app.tags:
			var tag_name := str(tag).strip_edges()
			if not tag_name.is_empty() and not available.has(tag_name):
				available.append(tag_name)
	return available


func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()

	var available: Array = _collect_available_tags()
	if available.is_empty():
		# No curated tags for this game — leave section empty until Steam/app config provides them.
		return

	for tag in available:
		_add_tag_checkbox(str(tag))
	_sync_checkboxes_to_current_tags()


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


func on_tag_toggled(toggled_on: bool, tag: String) -> void:
	if toggled_on:
		if not current_tags.has(tag):
			current_tags.append(tag)
	else:
		current_tags.erase(tag)
	AppLogger.info("Tag list is now " + str(current_tags))
	tags_changed.emit()
