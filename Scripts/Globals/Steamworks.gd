extends Node

const LibraryScanner = preload("res://Scripts/steam_library_scanner.gd")
const MasterList = preload("res://Scripts/steam_master_app_list.gd")

@export var steam_apps: Array[SteamApp] = []

var _curated_steam_apps: Array[SteamApp] = []
var _name_fetcher: Node = null
var _master_list_loader: Node = null
var _is_shutting_down: bool = false
var _library_loaded: bool = false

var app_id:int = -1;

var is_initialized:bool = false;

var tos_url = "https://steamcommunity.com/sharedfiles/workshoplegalagreement"
var formatting_url = "https://steamcommunity.com/comment/ForumTopic/formattinghelp"

var ugc_items:Dictionary[int, Dictionary] = {}

var current_steam_app:SteamApp:
	get():
		if app_id == -1:
			return null
		for app in steam_apps:
			if app.app_id == app_id:
				return app
		return null
		
var current_ugc_item:Dictionary = {}

signal steamworks_init
signal steamworks_ugc_items_retrieved

signal current_stats_received()
signal item_created(item_id: int)
signal item_updated(item_id: int)
signal item_deleted(result:int, file_id: int)
signal item_downloaded(result:int, file_id: int, app_id:int)
signal item_installed(app_id:int, file_id: int)
signal ugc_query_completed(handle: int, result:int, results_returned:int, total_matching:int, cached:bool)
signal steam_apps_loaded
signal steam_app_names_updated
signal steam_context_changed

#
# Initialization Methods
#

func _ready():
	_curated_steam_apps = steam_apps.duplicate()
	_name_fetcher = get_node_or_null("SteamAppNameFetcher")
	if _name_fetcher:
		_name_fetcher.names_updated.connect(_on_steam_app_names_updated)
	_master_list_loader = get_node_or_null("SteamMasterAppListLoader")
	if _master_list_loader:
		_master_list_loader.master_list_ready.connect(_on_master_list_ready)
	if MasterList.ensure_loaded():
		call_deferred("refresh_steam_apps_from_library")

	if Engine.has_singleton("Steam"):
		connect_signals()
		AppLogger.info("Successfully initialized Steamworks callbacks.")


func call_on_apps_loaded(callback: Callable) -> void:
	if _library_loaded and not steam_apps.is_empty():
		callback.call()
	else:
		steam_apps_loaded.connect(callback, CONNECT_ONE_SHOT)


func refresh_steam_apps_from_library() -> void:
	var result: Dictionary = LibraryScanner.discover()
	if not result.get("ok", false):
		AppLogger.error("Steam library scan failed: " + str(result["error"]))
		if _curated_steam_apps.is_empty():
			steam_apps = []
		else:
			steam_apps = _curated_steam_apps.duplicate()
		_library_loaded = true
		steam_apps_loaded.emit()
		return

	steam_apps = _build_steam_apps_from_scan(result["apps"])
	_apply_cached_names_to_apps()
	_library_loaded = true
	AppLogger.info("Loaded %d games from local Steam account." % steam_apps.size())
	steam_apps_loaded.emit()
	fetch_unresolved_names()


func _build_steam_apps_from_scan(entries: Array) -> Array[SteamApp]:
	var curated_by_id: Dictionary = {}
	for app in _curated_steam_apps:
		curated_by_id[app.app_id] = app

	var built: Array[SteamApp] = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var app_id: int = int(entry.get("app_id", -1))
		if app_id <= 0:
			continue
		var app := SteamApp.new()
		app.app_id = app_id
		app.name = str(entry.get("name", "App %d" % app_id))
		if curated_by_id.has(app_id):
			var curated: SteamApp = curated_by_id[app_id]
			if not curated.tags.is_empty():
				app.tags = curated.tags
			if curated.icon:
				app.icon = curated.icon
		if app.icon == null:
			app.icon = LibraryScanner.get_local_icon(app_id)
		built.append(app)
	return built


func _on_steam_app_names_updated() -> void:
	_apply_cached_names_to_apps()
	var changed := false
	if _name_fetcher:
		var cache: Dictionary = LibraryScanner.load_name_cache()
		for app in steam_apps:
			var cached_name := str(cache.get(str(app.app_id), ""))
			if cached_name.is_empty():
				continue
			if app.name != cached_name:
				app.name = cached_name
				changed = true
	if changed:
		steam_app_names_updated.emit()


func get_cached_app_name(app_id: int) -> String:
	if _name_fetcher:
		return _name_fetcher.get_cached_name(app_id)
	return ""


func _on_master_list_ready(count: int) -> void:
	if not _library_loaded:
		refresh_steam_apps_from_library()
	elif count > 0:
		_apply_cached_names_to_apps()
		steam_app_names_updated.emit()
		fetch_unresolved_names()


func fetch_unresolved_names() -> void:
	if _name_fetcher == null or steam_apps.is_empty():
		return
	var missing: Array[int] = []
	for app in steam_apps:
		if app.name.begins_with("App "):
			missing.append(app.app_id)
	if missing.is_empty():
		return
	AppLogger.info("Resolving names for %d games (Store API)…" % missing.size())
	_name_fetcher.fetch_missing(missing)


func _apply_cached_names_to_apps() -> void:
	for app in steam_apps:
		if not app.name.begins_with("App "):
			continue
		var cached_name := MasterList.lookup_app_name(app.app_id)
		if cached_name.is_empty() and _name_fetcher:
			cached_name = _name_fetcher.get_cached_name(app.app_id)
		if not cached_name.is_empty():
			app.name = cached_name


func prioritize_app_names(app_ids: Array) -> void:
	if _name_fetcher:
		_name_fetcher.prioritize(app_ids)


func start_steam() -> void:
	ensure_initialized_for_app(app_id)


func shutdown_steam() -> void:
	if is_initialized and Engine.has_singleton("Steam"):
		Steam.steamShutdown()
	is_initialized = false
	ugc_items.clear()
	_ugc_request_handle = -1
	_page_number = 1
	steam_context_changed.emit()


func shutdown() -> void:
	if _is_shutting_down:
		return
	_is_shutting_down = true
	if _name_fetcher:
		_name_fetcher.stop()
	if _master_list_loader and _master_list_loader.has_method("stop"):
		_master_list_loader.stop()
	shutdown_steam()


func ensure_initialized_for_app(target_app_id: int) -> void:
	if not Engine.has_singleton("Steam"):
		AppLogger.error("GodotSteam is not initialized!")
		return
	if target_app_id <= 0:
		AppLogger.error("Can't init Steamworks, app ID not selected!")
		return
	if is_initialized and app_id == target_app_id:
		return
	if is_initialized:
		shutdown_steam()
	app_id = target_app_id
	initialize()


func connect_signals():
	# Steam.connect("stea", on_steamworks_error, CONNECT_PERSIST)
	Steam.current_stats_received.connect(on_current_stats_received)
	
	Steam.item_created.connect(on_item_created)
	Steam.item_updated.connect(on_item_updated)
	Steam.item_deleted.connect(on_item_deleted)
	Steam.item_downloaded.connect(on_item_downloaded)
	Steam.item_installed.connect(on_item_installed)
	Steam.overlay_toggled.connect(on_overlay_toggled)
	Steam.ugc_query_completed.connect(on_ugc_query_completed)
	Steam.dlc_installed.connect(on_dlc_installed)
	Steam.user_subscribed_items_list_changed.connect(on_user_subscribed_items_list_changed)

func initialize():
	if is_initialized:
		print("Not initializing, already initialized.")
		return
	
	if app_id == -1:
		AppLogger.error("Can't init Steamworks, app ID not selected!")
		return
	
	var result:Dictionary = Steam.steamInitEx(app_id, false)
	var success = result["status"] == Steam.STEAM_API_INIT_RESULT_OK
	if success:
		AppLogger.info("Successfully initialized Steamworks!")
		is_initialized = true
		
		steamworks_init.emit()
		steam_context_changed.emit()
	else:
		AppLogger.error("Steam failed to initialize. Status: " + result["status"] + ", Info: " + result["verbal"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


func _exit_tree() -> void:
	shutdown()


func _process(_delta: float) -> void:
	if is_initialized and Engine.has_singleton("Steam"):
		Steam.run_callbacks()
	
#
# Query Methods
#

func get_app_id() -> int:
	return Steam.current_app_id

func get_user_display_name() -> String:
	return Steam.getPersonaName()

func get_user_steam_id() -> int:
	return Steam.getSteamID()

func get_ugc_items() -> Dictionary[int, Dictionary]:
	return ugc_items

#
# Action Methods
#

func call_on_init(callback: Callable):
	if is_initialized:
		callback.call()
	else:
		steamworks_init.connect(callback)

func open_url(url:String):
	if is_initialized:
		Steam.activateGameOverlayToWebPage(url, Steam.OverlayToWebPageMode.OVERLAY_TO_WEB_PAGE_MODE_DEFAULT)
	else:
		OS.shell_open(url)

func open_tos_url() -> void:
	open_url(tos_url)

func create_workshop_item(type:Steam.WorkshopFileType):
	Steam.createItem(Steam.current_app_id, type)


func delete_workshop_item(file_id: int) -> void:
	if not is_initialized:
		AppLogger.error("Could not delete workshop item, Steam not initialized!")
		return
	if file_id <= 0:
		AppLogger.error("Invalid workshop item id.")
		return
	AppLogger.info("Deleting workshop item " + str(file_id) + "…")
	Steam.deleteItem(file_id)

var _ugc_update_handle:int = -1

func update_workshop_item(file_id:int, new_params:Dictionary, change_notes:String):
	_ugc_update_handle = Steam.startItemUpdate(Steam.current_app_id, file_id)

	# TODO: Allow for setting the title and description in other languages
	Steam.setItemUpdateLanguage(_ugc_update_handle, "english")

	Steam.setItemTitle(_ugc_update_handle, new_params["title"])
	Steam.setItemTags(_ugc_update_handle, new_params["tags"].split(','))
	Steam.setItemVisibility(_ugc_update_handle, new_params["visibility"])

	if new_params["description"] != "":
		print("Uploading description...")
		Steam.setItemDescription(_ugc_update_handle, new_params["description"])

	if new_params["upload_path"] != "":
		print("Uploading workshop files: " + new_params["upload_path"])
		Steam.setItemContent(_ugc_update_handle, new_params["upload_path"])

	if new_params["preview_path"] != "":
		AppLogger.info("Uploading item preview: " + new_params["preview_path"])
		Steam.setItemPreview(_ugc_update_handle, new_params["preview_path"])

	# Result will be received by on_item_updated
	Steam.submitItemUpdate(_ugc_update_handle, change_notes)

var _ugc_request_handle:int = -1
var _page_number:int = 1

func query_published_items(page:int = 1):
	if not is_initialized:
		AppLogger.error("Could not query published items, Steam not initialized!")
		return
	
	if _ugc_request_handle != -1:
		AppLogger.error("Could not query published items, request already in progress!")
		return
	
	var list = Steam.UserUGCList.USER_UGC_LIST_PUBLISHED
	var type = Steam.UGCMatchingUGCType.UGC_MATCHING_UGC_TYPE_ITEMS
	var sort = Steam.UserUGCListSortOrder.USER_UGC_LIST_SORT_ORDER_CREATION_ORDER_DESC
	
	_ugc_request_handle = Steam.createQueryUserUGCRequest(
		get_user_steam_id(),
		list, type, sort,
		get_app_id(), get_app_id(), page)
		
	# Return the full description.
	Steam.setReturnLongDescription(_ugc_request_handle, true)
	
	Steam.sendQueryUGCRequest(_ugc_request_handle)

func fetch_queried_ugc_items(count: int):
	for i in range(count):
		var item = Steam.getQueryUGCResult(_ugc_request_handle, i)
		ugc_items.set(item["file_id"], item)
		
		# Seems to always be 0 for Binding of Isaac.
		# var num_kv_tags = Steam.getQueryUGCNumKeyValueTags(_ugc_request_handle, i)
		# print("Entry has " + str(num_kv_tags) + " key/value tags")
		
		var preview_url = Steam.getQueryUGCPreviewURL(_ugc_request_handle, i)
		item["preview_url"] = preview_url

#
# Signal Callbacks
#

func on_current_stats_received():
	AppLogger.info("[STEAM] Current stats received")
	emit_signal("current_stats_received")
	
func on_item_created(result:int, file_id: int, accept_tos:bool):
	AppLogger.info("[STEAM] Item created: " + str(file_id) + " (result: " + SteamResult.stringify(result) + ")")
	emit_signal("item_created", result, file_id, accept_tos)

	if accept_tos:
		open_tos_url()
	
func on_item_updated(result: int, accept_tos:bool):
	AppLogger.info("[STEAM] Item updated: " + SteamResult.stringify(result))
	emit_signal("item_updated", result, accept_tos)

	if accept_tos:
		open_tos_url()
	
func on_item_deleted(result:int, file_id: int):
	AppLogger.info("[STEAM] Item deleted: " + str(file_id) + " (result: " + SteamResult.stringify(result) + ")")
	if result == Steam.RESULT_OK or result == Steam.RESULT_ITEM_DELETED:
		ugc_items.erase(file_id)
		if int(current_ugc_item.get("file_id", -1)) == file_id:
			current_ugc_item = {}
		steamworks_ugc_items_retrieved.emit()
	else:
		AppLogger.error("Failed to delete workshop item " + str(file_id))
	emit_signal("item_deleted", result, file_id)
	
func on_item_downloaded(result:int, file_id: int, _app_id:int):
	AppLogger.info("[STEAM] Item downloaded: " + str(file_id) + " (result: " + SteamResult.stringify(result) + ")")
	emit_signal("item_downloaded", result, file_id, _app_id)
	
func on_item_installed(_app_id:int, file_id: int):
	AppLogger.info("[STEAM] Item installed: " + str(file_id))
	emit_signal("item_installed", _app_id, file_id)
	
func on_ugc_query_completed(handle: int, result:int, results_returned:int, total_matching:int, cached:bool):
	AppLogger.info("[STEAM] UGC query completed (result: " + SteamResult.stringify(result) + "), got " + str(results_returned) + " items")
	emit_signal("ugc_query_completed", handle, result, results_returned, total_matching, cached)
	
	if result == Steam.RESULT_OK:
		fetch_queried_ugc_items(results_returned)
	else:
		AppLogger.error("Couldn't get published UGC: " + SteamResult.stringify(result))
	
	_ugc_request_handle = -1
		
	if results_returned == 50:
		_page_number += 1
		query_published_items(_page_number)
	else:
		steamworks_ugc_items_retrieved.emit()
	
func on_dlc_installed(_app_id:int):
	AppLogger.info("[STEAM] DLC installed: " + str(_app_id))
	emit_signal("dlc_installed", _app_id)
	
func on_user_subscribed_items_list_changed(_app_id:int):
	AppLogger.info("[STEAM] User subscribed items list changed")
	emit_signal("user_subscribed_items_list_changed", _app_id)

func on_overlay_toggled(active:bool, user_initiated:bool, _app_id:int):
	AppLogger.info("[STEAM] Overlay toggled: " + str(active) + " (user? " + str(user_initiated) + ")")
	emit_signal("overlay_toggled", active, user_initiated)
