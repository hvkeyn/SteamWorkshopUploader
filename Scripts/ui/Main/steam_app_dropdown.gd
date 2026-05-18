extends OptionButton

const MasterList = preload("res://Scripts/steam_master_app_list.gd")

var _prefs_loaded: bool = false
var _apps_loaded: bool = false
var _initial_selection_applied: bool = false
var _filter_query: String = ""


func _ready() -> void:
	if has_node("%SteamAppFilter"):
		%SteamAppFilter.text_changed.connect(_on_filter_changed)

	Steamworks.steam_apps_loaded.connect(_on_steam_apps_loaded)
	Steamworks.steam_app_names_updated.connect(_on_steam_app_names_updated)
	Steamworks.steam_context_changed.connect(_on_steam_context_changed)
	Steamworks.call_on_apps_loaded(_on_apps_ready)
	UserPrefHandler.call_on_load(_on_user_prefs_loaded)

	Steamworks.call_on_init(on_steamworks_init)


func _on_apps_ready() -> void:
	load_entries()
	_apps_loaded = true
	_try_apply_initial_selection()


func load_entries() -> void:
	if has_node("%SteamAppFilter"):
		_filter_query = %SteamAppFilter.text.strip_edges()

	var selected_app_id := -1
	if get_item_count() > 0 and selected >= 0:
		selected_app_id = get_item_id(selected)

	set_block_signals(true)
	clear()

	var match_count := 0
	for app in Steamworks.steam_apps:
		if not _matches_filter(app):
			continue
		match_count += 1
		var label := _display_name(app)
		add_item(label, app.app_id)
		if app.icon:
			set_item_icon(get_item_index(app.app_id), app.icon)

	if match_count == 0:
		add_item("(No games — clear search or wait for library)", -1)
	elif selected_app_id > 0:
		var restored := get_item_index(selected_app_id)
		if restored >= 0:
			selected = restored

	set_block_signals(false)
	_update_initialize_button()


func _display_name(app: SteamApp) -> String:
	if not app.name.begins_with("App "):
		return app.name
	var from_master := MasterList.lookup_app_name(app.app_id)
	if not from_master.is_empty():
		return from_master
	return app.name


func _matches_filter(app: SteamApp) -> bool:
	if _filter_query.is_empty():
		return true
	var query := _filter_query.to_lower()
	if query in _display_name(app).to_lower():
		return true
	return query in str(app.app_id)


func _on_filter_changed(_new_text: String) -> void:
	load_entries()
	_prioritize_visible_app_names()


func _prioritize_visible_app_names() -> void:
	if _filter_query.length() < 2:
		return
	var ids: Array[int] = []
	for app in Steamworks.steam_apps:
		if _matches_filter(app):
			ids.append(app.app_id)
	Steamworks.prioritize_app_names(ids)


func _on_user_prefs_loaded() -> void:
	_prefs_loaded = true
	_try_apply_initial_selection()


func _on_steam_apps_loaded() -> void:
	load_entries()
	_apps_loaded = true
	_try_apply_initial_selection()


func _on_steam_app_names_updated() -> void:
	load_entries()


func _on_steam_context_changed() -> void:
	_update_initialize_button()


func _try_apply_initial_selection() -> void:
	if not (_prefs_loaded and _apps_loaded):
		return
	if _initial_selection_applied:
		return
	_initial_selection_applied = true

	var last_app_id: int = UserPreferences.fetch().last_app_id
	if last_app_id > 0:
		var index := get_item_index(last_app_id)
		if index >= 0:
			set_block_signals(true)
			selected = index
			set_block_signals(false)
			_apply_app_selection(last_app_id)
			return


func _on_item_selected(index: int) -> void:
	if index < 0:
		return
	var app_id := get_item_id(index)
	if app_id <= 0:
		return
	_apply_app_selection(app_id)


func _apply_app_selection(app_id: int) -> void:
	if app_id <= 0:
		return

	var index := get_item_index(app_id)
	var app_name := get_item_text(index) if index >= 0 else ("App %d" % app_id)

	AppLogger.info("Selected app: " + app_name + " (" + str(app_id) + ")")

	if UserPreferences.fetch().last_app_id != app_id:
		UserPreferences.fetch().last_app_id = app_id

	if Steamworks.is_initialized and Steamworks.app_id != app_id:
		Steamworks.shutdown_steam()

	Steamworks.app_id = app_id

	if UserPreferences.fetch().auto_init:
		Steamworks.ensure_initialized_for_app(app_id)

	_update_initialize_button()
	_prioritize_visible_app_names()


func _update_initialize_button() -> void:
	var btn := get_node_or_null("%ButtonSteamInitialize")
	if btn == null:
		return
	var app_id := get_item_id(selected) if selected >= 0 else -1
	if app_id <= 0:
		app_id = Steamworks.app_id
	var connected := (
		Steamworks.is_initialized
		and app_id > 0
		and Steamworks.app_id == app_id
	)
	btn.disabled = connected
	btn.text = (
		"Steam connected to selected game"
		if connected
		else "Initialize Steam Connection"
	)


func on_steamworks_init() -> void:
	_update_initialize_button()
