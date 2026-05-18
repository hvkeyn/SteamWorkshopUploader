extends Button

var _confirm: ConfirmationDialog


func _ready() -> void:
	disabled = true
	pressed.connect(_on_pressed)
	Steamworks.steamworks_ugc_items_retrieved.connect(_update_state)
	Steamworks.steam_context_changed.connect(_update_state)
	if has_node("%DropdownWorkshopItem"):
		%DropdownWorkshopItem.item_selected.connect(func(_i): _update_state())


func _update_state() -> void:
	disabled = not Steamworks.is_initialized or _get_selected_item_id() <= 0


func _get_selected_item_id() -> int:
	if not has_node("%DropdownWorkshopItem"):
		return -1
	return %DropdownWorkshopItem.get_selected_item_id()


func _on_pressed() -> void:
	var file_id := _get_selected_item_id()
	if file_id <= 0:
		AppLogger.error("Select a workshop item to delete.")
		return

	var label := str(file_id)
	if Steamworks.ugc_items.has(file_id):
		var item: Dictionary = Steamworks.ugc_items[file_id]
		var title := str(item.get("title", ""))
		if not title.is_empty():
			label = title + " (" + str(file_id) + ")"

	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.ok_button_text = "Delete"
		_confirm.cancel_button_text = "Cancel"
		_confirm.confirmed.connect(_on_delete_confirmed)
		get_tree().root.add_child(_confirm)

	_confirm.dialog_text = (
		"Permanently delete this Workshop item?\n\n%s\n\nThis cannot be undone."
		% label
	)
	_confirm.set_meta("file_id", file_id)
	_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _confirm == null:
		return
	var file_id: int = int(_confirm.get_meta("file_id", -1))
	if file_id <= 0:
		return
	disabled = true
	Steamworks.delete_workshop_item(file_id)
