extends ItemList

## Scrollable Steam library list with search filter (replaces OptionButton popup).

const MasterList = preload("res://Scripts/steam_master_app_list.gd")
const MAX_VISIBLE_WITHOUT_FILTER := 80

var _prefs_loaded: bool = false
var _apps_loaded: bool = false
var _initial_selection_applied: bool = false
var _filter_query: String = ""
var _row_app_ids: Array[int] = []


func _ready() -> void:
	allow_reselect = true
	select_mode = ItemList.SELECT_SINGLE

	if has_node("%SteamAppFilter"):
		%SteamAppFilter.text_changed.connect(_on_filter_changed)
		%SteamAppFilter.placeholder_text = "Search game by name or AppID…"

	Steamworks.steam_apps_loaded.connect(_on_steam_apps_loaded)
	Steamworks.steam_app_names_updated.connect(_on_steam_app_names_updated)
	Steamworks.steam_context_changed.connect(_on_steam_context_changed)
	Steamworks.call_on_apps_loaded(_on_apps_ready)
	UserPrefHandler.call_on_load(_on_user_prefs_loaded)

	Steamworks.call_on_init(on_steamworks_init)


func _on_apps_ready() -> void:
	rebuild_list()
	_apps_loaded = true
	_try_apply_initial_selection()


func rebuild_list() -> void:
	if has_node("%SteamAppFilter"):
		_filter_query = %SteamAppFilter.text.strip_edges()

	var selected_app_id := get_selected_app_id()

	clear()
	_row_app_ids.clear()

	var match_count := 0
	var truncated := false
	var shown_ids: Dictionary = {}
	for app in Steamworks.steam_apps:
		if not _matches_filter(app):
			continue
		if _filter_query.is_empty() and match_count >= MAX_VISIBLE_WITHOUT_FILTER:
			truncated = true
			break
		match_count += 1
		var row := get_item_count()
		add_item(_display_name(app))
		set_item_metadata(row, app.app_id)
		_row_app_ids.append(app.app_id)
		shown_ids[app.app_id] = true

	if truncated and selected_app_id > 0 and not shown_ids.has(selected_app_id):
		for app in Steamworks.steam_apps:
			if app.app_id == selected_app_id:
				var row := get_item_count()
				add_item(_display_name(app))
				set_item_metadata(row, app.app_id)
				_row_app_ids.append(app.app_id)
				match_count += 1
				break

	if match_count == 0:
		if _filter_query.is_empty():
			add_item("(No games in library — check Steam login)")
		else:
			add_item('(No matches for "%s")' % _filter_query)
		set_item_metadata(0, -1)
	elif truncated:
		var hint_row := get_item_count()
		add_item("… type in search to see more (%d games total)" % Steamworks.steam_apps.size())
		set_item_metadata(hint_row, -1)
	elif selected_app_id > 0:
		_select_app_id(selected_app_id, false)

	_update_initialize_button()


func _resolve_app_name(app: SteamApp) -> String:
	if not app.name.begins_with("App "):
		return app.name
	var from_master := MasterList.lookup_app_name(app.app_id)
	if not from_master.is_empty():
		app.name = from_master
		return from_master
	var from_cache := Steamworks.get_cached_app_name(app.app_id)
	if not from_cache.is_empty():
		app.name = from_cache
		return from_cache
	return app.name


func _display_name(app: SteamApp) -> String:
	return _resolve_app_name(app)


func get_selected_app_id() -> int:
	var rows := get_selected_items()
	if rows.is_empty():
		return -1
	var row: int = rows[0]
	if row < 0 or row >= _row_app_ids.size():
		return -1
	var app_id: int = _row_app_ids[row]
	if app_id <= 0:
		return -1
	return app_id


func _select_app_id(app_id: int, apply: bool) -> void:
	for row in range(_row_app_ids.size()):
		if _row_app_ids[row] == app_id:
			select(row)
			if apply:
				_apply_app_selection(app_id)
			return


func _matches_filter(app: SteamApp) -> bool:
	if _filter_query.is_empty():
		return true
	var query := _filter_query.to_lower()
	if query in _resolve_app_name(app).to_lower():
		return true
	return query in str(app.app_id)


func _on_filter_changed(new_text: String) -> void:
	_filter_query = new_text.strip_edges()
	var keep_id := get_selected_app_id()
	rebuild_list()
	if keep_id > 0 and _matches_filter_app_id(keep_id):
		_select_app_id(keep_id, false)
	else:
		deselect_all()
	_prioritize_visible_app_names()


func _matches_filter_app_id(app_id: int) -> bool:
	for app in Steamworks.steam_apps:
		if app.app_id == app_id:
			return _matches_filter(app)
	return false


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
	rebuild_list()
	_apps_loaded = true
	_try_apply_initial_selection()


func _on_steam_app_names_updated() -> void:
	var selected := get_selected_app_id()
	rebuild_list()
	if selected > 0:
		_select_app_id(selected, false)


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
		_select_app_id(last_app_id, true)


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _row_app_ids.size():
		return
	var app_id := _row_app_ids[index]
	if app_id <= 0:
		return
	_apply_app_selection(app_id)


func _on_item_activated(index: int) -> void:
	_on_item_selected(index)


func _apply_app_selection(app_id: int) -> void:
	if app_id <= 0:
		return

	var app_name := ""
	for app in Steamworks.steam_apps:
		if app.app_id == app_id:
			app_name = _resolve_app_name(app)
			break
	if app_name.is_empty():
		app_name = "App %d" % app_id

	var needs_reinit := not Steamworks.is_initialized or Steamworks.app_id != app_id
	if not needs_reinit:
		_update_initialize_button()
		return

	AppLogger.info("Selected app: " + app_name + " (" + str(app_id) + ")")

	if UserPreferences.fetch().last_app_id != app_id:
		UserPreferences.fetch().last_app_id = app_id

	if Steamworks.is_initialized:
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
	var selected := get_selected_app_id()
	if selected <= 0:
		selected = Steamworks.app_id
	var connected := (
		Steamworks.is_initialized
		and selected > 0
		and Steamworks.app_id == selected
	)
	btn.disabled = connected
	btn.text = (
		"Steam connected to selected game"
		if connected
		else "Initialize Steam Connection"
	)


func on_steamworks_init() -> void:
	_update_initialize_button()
