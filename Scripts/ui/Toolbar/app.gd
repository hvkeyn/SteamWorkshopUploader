extends PopupMenu

enum Item {
	QUIT,
}

const SHORTCUT_QUIT = preload("res://resources/shortcuts/quit.tres")

func _ready() -> void:
	self.set_item_shortcut(Item.QUIT, SHORTCUT_QUIT)

func _on_index_pressed(index: int) -> void:
	var id = get_item_id(index)
	match id:
		Item.QUIT:
			AppLogger.info("Quitting application! Bye :)")
			Steamworks.shutdown()
			get_tree().quit(0)
		_:
			AppLogger.error("Unknown item pressed: App#" + str(index))
