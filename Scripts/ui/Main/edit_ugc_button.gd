extends Button

func _on_pressed() -> void:
	var selected_id: int = %DropdownWorkshopItem.get_selected_item_id()
	if selected_id <= 0:
		return
	if not Steamworks.ugc_items.has(selected_id):
		AppLogger.error("Workshop item %d is not loaded." % selected_id)
		return
	var item: Dictionary = Steamworks.ugc_items[selected_id]
	if not Steamworks.ugc_item_belongs_to_app(item, Steamworks.app_id):
		AppLogger.error(
			"Workshop item %d belongs to another game (not App %d)."
			% [selected_id, Steamworks.app_id]
		)
		return

	AppLogger.info("Editing UGC Item: " + str(selected_id))
	Steamworks.current_ugc_item = item
	get_tree().change_scene_to_file("res://scenes/ui/EditItem.tscn")
