extends Label

func _ready() -> void:
	Steamworks.steam_context_changed.connect(_refresh)
	Steamworks.steam_app_names_updated.connect(_refresh)
	Steamworks.steamworks_init.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not Steamworks.is_initialized or Steamworks.app_id <= 0:
		text = "Items for: (not connected)"
		return

	var app_name := ""
	for app in Steamworks.steam_apps:
		if app.app_id == Steamworks.app_id:
			app_name = app.name
			break
	if app_name.is_empty():
		app_name = Steamworks.get_cached_app_name(Steamworks.app_id)
	if app_name.is_empty() or app_name.begins_with("App "):
		app_name = "App %d" % Steamworks.app_id

	text = "Items for: %s" % app_name
