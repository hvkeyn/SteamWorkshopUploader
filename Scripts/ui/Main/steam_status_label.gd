extends Label

func _ready() -> void:
	Steamworks.steam_context_changed.connect(_refresh)
	Steamworks.call_on_init(_refresh)
	text = "Steam Status: Not Connected"
	_refresh()


func _refresh() -> void:
	if Steamworks.is_initialized:
		text = build_initialized_text()
	elif Steamworks.app_id > 0:
		text = (
			"Steam Status: Not connected\n"
			+ "Selected App ID: %d — press Initialize Steam Connection" % Steamworks.app_id
		)
	else:
		text = "Steam Status: Not Connected"


func build_initialized_text() -> String:
	var result := ""
	result += "Steam Status: Initialized"
	result += "\nSteam User: " + Steamworks.get_user_display_name()
	result += " (" + str(Steamworks.get_user_steam_id()) + ")"
	result += "\nSteam App ID: " + str(Steamworks.get_app_id())
	return result
