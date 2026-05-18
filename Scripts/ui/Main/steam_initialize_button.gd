extends Button

func _ready() -> void:
	Steamworks.steam_context_changed.connect(_update_state)
	Steamworks.call_on_init(_update_state)
	_update_state()


func _get_selected_app_id() -> int:
	var list := get_node_or_null("%SteamAppList")
	if list and list.has_method("get_selected_app_id"):
		var picked: int = list.get_selected_app_id()
		if picked > 0:
			return picked
	return Steamworks.app_id


func _on_pressed() -> void:
	var app_id := _get_selected_app_id()
	if app_id <= 0:
		AppLogger.error("Select a game from the list first.")
		return
	Steamworks.ensure_initialized_for_app(app_id)


func _update_state() -> void:
	var selected := _get_selected_app_id()
	var connected := (
		Steamworks.is_initialized
		and selected > 0
		and Steamworks.app_id == selected
	)
	disabled = connected
	text = (
		"Steam connected to selected game"
		if connected
		else "Initialize Steam Connection"
	)


func on_steamworks_init() -> void:
	_update_state()
