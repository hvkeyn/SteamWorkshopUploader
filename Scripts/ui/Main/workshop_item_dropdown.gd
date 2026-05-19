extends OptionButton

# We have to store item IDs separate,
# because setting the OptionButton index to a high number breaks.
var id_mapping: Array[int] = []


func _ready() -> void:
	Steamworks.steamworks_ugc_items_retrieved.connect(on_ugc_items_retrieved)
	Steamworks.steam_context_changed.connect(_on_steam_context_changed)
	_reset_placeholder(_placeholder_text())


func _on_steam_context_changed() -> void:
	Steamworks.current_ugc_item = {}
	_reset_placeholder(_placeholder_text())


func _placeholder_text() -> String:
	if not Steamworks.is_initialized:
		return "(connect Steam for selected game)"
	if Steamworks.app_id <= 0:
		return "(select a game)"
	return "(press Refresh Workshop List)"


func _reset_placeholder(text: String) -> void:
	id_mapping.clear()
	clear()
	add_item(text, 0)
	disabled = true
	selected = 0
	_set_action_buttons_enabled(false)


func on_ugc_items_retrieved() -> void:
	if not Steamworks.is_initialized or Steamworks.app_id <= 0:
		_reset_placeholder(_placeholder_text())
		return

	var items := Steamworks.get_ugc_items_for_current_app()
	id_mapping.clear()
	clear()

	if items.is_empty():
		_reset_placeholder("(no items for this game)")
		return

	for item_id in items:
		var item: Dictionary = items[item_id]
		process_item(item)

	disabled = false
	if id_mapping.size() > 0:
		selected = 0

	var item_id := get_selected_item_id()
	_set_action_buttons_enabled(item_id > 0)


func process_item(item: Dictionary) -> void:
	if not Steamworks.ugc_item_belongs_to_app(item, Steamworks.app_id):
		return

	var file_id: int = int(item.get("file_id", 0))
	if file_id <= 0:
		return

	var title: String = str(item.get("title", "Untitled")).strip_edges()
	if title.is_empty():
		title = "Untitled"

	var item_label := "%s (%d)" % [title, file_id]
	id_mapping.append(file_id)
	add_item(item_label)


func _on_item_selected(index: int) -> void:
	if index < 0:
		return
	var item_name := get_item_text(index)
	AppLogger.info("Steam Workshop Item selected: " + item_name)

	var item_id := get_selected_item_id()
	_set_action_buttons_enabled(item_id > 0)


func get_selected_item_id() -> int:
	if id_mapping.is_empty():
		return -1
	if selected < 0 or selected >= id_mapping.size():
		return -1
	return id_mapping[selected]


func _set_action_buttons_enabled(enabled: bool) -> void:
	if has_node("%ButtonEditUGC"):
		%ButtonEditUGC.disabled = not enabled
	if has_node("%ButtonDeleteUGC"):
		%ButtonDeleteUGC.disabled = not enabled
