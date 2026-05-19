extends Node

const LibraryScanner = preload("res://Scripts/steam_library_scanner.gd")
const MasterList = preload("res://Scripts/steam_master_app_list.gd")
const WorkshopPreview = preload("res://Scripts/workshop_preview.gd")
const UploadPaths = preload("res://Scripts/workshop_upload_paths.gd")
const UgcItemRegistry = preload("res://Scripts/ugc_item_registry.gd")
const UgcDraftStore = preload("res://Scripts/ugc_draft_store.gd")

const UGC_QUERY_NONE := -1
const UGC_QUERY_PUBLISHED := 0
const UGC_QUERY_DETAILS := 1

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
signal workshop_upload_completed(result: int, file_id: int, need_accept_tos: bool)
signal workshop_upload_log(line: String)
signal item_deleted(result:int, file_id: int)
signal item_downloaded(result:int, file_id: int, app_id:int)
signal item_installed(app_id:int, file_id: int)
signal ugc_query_completed(handle: int, result:int, results_returned:int, total_matching:int, cached:bool)
signal steam_apps_loaded
signal steam_app_names_updated
signal steam_context_changed
signal overlay_toggled(active: bool, user_initiated: bool)
signal dlc_installed(app_id: int)
signal user_subscribed_items_list_changed(app_id: int)

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
	current_ugc_item = {}
	_ugc_request_handle = -1
	_page_number = 1
	_ugc_query_phase = UGC_QUERY_NONE
	_details_ids_queue = PackedInt64Array()
	_details_offset = 0
	steam_context_changed.emit()
	steamworks_ugc_items_retrieved.emit()


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
		_sync_steam_appid_file(app_id)

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


func get_ugc_items_for_current_app() -> Dictionary[int, Dictionary]:
	var out: Dictionary[int, Dictionary] = {}
	if app_id <= 0:
		return out
	for file_id in ugc_items:
		var item: Dictionary = ugc_items[file_id]
		if ugc_item_belongs_to_app(item, app_id):
			out[file_id] = item
	return out


func ugc_item_belongs_to_app(item: Dictionary, target_app_id: int) -> bool:
	if target_app_id <= 0:
		return false
	var consumer := int(item.get("consumer_app_id", 0))
	var creator := int(item.get("creator_app_id", 0))
	if consumer > 0:
		return consumer == target_app_id
	if creator > 0:
		return creator == target_app_id
	return true

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

func create_workshop_item(type: Steam.WorkshopFileType) -> void:
	if not is_initialized:
		AppLogger.error("Could not create workshop item, Steam not initialized!")
		return
	if app_id <= 0:
		AppLogger.error("Could not create workshop item, app ID not selected!")
		return
	Steam.createItem(app_id, type)


func delete_workshop_item(file_id: int) -> void:
	if not is_initialized:
		AppLogger.error("Could not delete workshop item, Steam not initialized!")
		return
	if file_id <= 0:
		AppLogger.error("Invalid workshop item id.")
		return
	AppLogger.info("Deleting workshop item " + str(file_id) + "…")
	Steam.deleteItem(file_id)

var _ugc_update_handle: int = -1
var _upload_file_id: int = -1
var _upload_temp_paths: Array[String] = []
var _last_upload_content_path: String = ""
var _last_upload_preview_path: String = ""
var _upload_staging_root: String = ""
var _upload_last_params: Dictionary = {}
var _upload_last_change_notes: String = ""
var _upload_retry_without_preview: bool = false
var _upload_was_metadata_only: bool = false
var upload_in_progress: bool = false


func is_upload_in_progress() -> bool:
	return upload_in_progress


func was_last_upload_metadata_only() -> bool:
	return _upload_was_metadata_only


func _upload_log(line: String) -> void:
	AppLogger.info(line)
	workshop_upload_log.emit(line)


func _is_valid_ugc_update_handle(handle: int) -> bool:
	if handle == 0 or handle == -1:
		return false
	return handle != Steam.UGC_UPDATE_HANDLE_INVALID


func _resolve_consumer_app_id(file_id: int, params: Dictionary) -> int:
	var consumer := int(params.get("consumer_app_id", 0))
	if consumer > 0:
		return consumer
	var creator := int(params.get("creator_app_id", 0))
	if creator > 0:
		return creator
	if ugc_items.has(file_id):
		var item: Dictionary = ugc_items[file_id]
		consumer = int(item.get("consumer_app_id", 0))
		if consumer > 0:
			return consumer
		creator = int(item.get("creator_app_id", 0))
		if creator > 0:
			return creator
	if app_id > 0:
		return app_id
	return int(get_app_id())


func _sync_steam_appid_file(target_app_id: int) -> void:
	if target_app_id <= 0:
		return
	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var path := project_dir.path_join("steam_appid.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(str(target_app_id))


func _begin_item_update(file_id: int, consumer_app_id: int) -> bool:
	# UGC list queries (_ugc_request_handle) and item updates (_ugc_update_handle) are independent.
	if consumer_app_id <= 0:
		_fail_upload("Could not determine the Steam App ID for this workshop item.")
		return false

	if not is_initialized or get_app_id() != consumer_app_id:
		AppLogger.info(
			"Re-initializing Steam for consumer app %d (was %d)…"
			% [consumer_app_id, get_app_id()]
		)
		ensure_initialized_for_app(consumer_app_id)

	if not is_initialized:
		_fail_upload("Steam is not initialized for app %d." % consumer_app_id)
		return false

	_sync_steam_appid_file(consumer_app_id)

	for _i in range(5):
		Steam.run_callbacks()

	_ugc_update_handle = Steam.startItemUpdate(consumer_app_id, file_id)
	if not _is_valid_ugc_update_handle(_ugc_update_handle):
		Steam.run_callbacks()
		_ugc_update_handle = Steam.startItemUpdate(consumer_app_id, file_id)

	if not _is_valid_ugc_update_handle(_ugc_update_handle):
		_fail_upload(
			"Steam refused to start the item update (invalid handle).\n"
			+ "App ID: %d, item: %d.\n"
			+ "Try: restart the Steam client, return to the main screen, "
			+ "re-initialize Steam for this game, then submit again."
			% [consumer_app_id, file_id]
		)
		return false

	return true


func update_workshop_item(file_id: int, new_params: Dictionary, change_notes: String) -> bool:
	file_id = int(file_id)
	if file_id <= 0:
		AppLogger.error("Invalid workshop file id.")
		return false
	if not is_initialized:
		AppLogger.error("Could not update workshop item, Steam not initialized!")
		return false
	if upload_in_progress:
		AppLogger.error("Another workshop upload is already in progress.")
		return false

	_upload_file_id = file_id
	_upload_temp_paths.clear()
	_last_upload_content_path = ""
	_last_upload_preview_path = ""
	_upload_staging_root = ""
	_upload_last_params = new_params.duplicate(true)
	_upload_last_change_notes = change_notes
	if not bool(new_params.get("retry_without_preview", false)):
		_upload_retry_without_preview = false
	_upload_was_metadata_only = bool(new_params.get("metadata_only", false))
	upload_in_progress = true

	var consumer_app_id := _resolve_consumer_app_id(file_id, new_params)
	if ugc_items.has(file_id):
		var item_meta: Dictionary = ugc_items[file_id]
		_upload_log(
			"Workshop item apps: creator=%d consumer=%d (upload uses consumer %d)."
			% [
				int(item_meta.get("creator_app_id", 0)),
				int(item_meta.get("consumer_app_id", 0)),
				consumer_app_id,
			]
		)
	_upload_log(
		"Starting Steam item update for workshop file %d (app %d)…"
		% [file_id, consumer_app_id]
	)
	var item_warning := _validate_workshop_item_before_upload(file_id, consumer_app_id)
	if item_warning != "":
		_fail_upload(item_warning)
		return false

	if not _begin_item_update(file_id, consumer_app_id):
		return false

	_upload_log("Setting language: english")
	Steam.setItemUpdateLanguage(_ugc_update_handle, "english")

	var title := str(new_params.get("title", "")).strip_edges()
	if title.is_empty():
		_fail_upload("Title is empty.")
		return false
	_upload_log("Setting title: " + title)
	Steam.setItemTitle(_ugc_update_handle, title)

	var tag_list := _parse_workshop_tags(str(new_params.get("tags", "")))
	if not tag_list.is_empty():
		_upload_log("Setting tags: " + ", ".join(tag_list))
		Steam.setItemTags(_ugc_update_handle, tag_list)
	else:
		_upload_log("No tags selected.")

	_upload_log("Setting visibility.")
	Steam.setItemVisibility(_ugc_update_handle, int(new_params.get("visibility", 0)))

	var description := str(new_params.get("description", ""))
	if description != "":
		_upload_log("Setting description (%d characters)." % description.length())
		Steam.setItemDescription(_ugc_update_handle, description)
	else:
		_upload_log("Skipping description update.")

	var upload_path := str(new_params.get("upload_path", ""))
	var preview_path := str(new_params.get("preview_path", ""))

	if bool(new_params.get("metadata_only", false)):
		upload_path = ""
		preview_path = ""
		_upload_log("Metadata-only upload (no files, no preview).")

	if preview_path != "":
		var preview_error := UploadPaths.validate_preview_file(preview_path)
		if preview_error != "":
			_fail_upload(preview_error)
			return false

	if upload_path != "":
		var content_error := UploadPaths.validate_content_folder(upload_path)
		if content_error != "":
			_fail_upload(content_error)
			return false
		var install_warning := UploadPaths.warn_if_game_install_folder(upload_path)
		if install_warning != "":
			_fail_upload(install_warning)
			return false
		upload_path = UploadPaths.to_steam_path(upload_path)

		var staged_content: Dictionary = UploadPaths.stage_content_for_steam(upload_path)
		if staged_content.has("error"):
			_fail_upload(str(staged_content["error"]))
			return false
		if str(staged_content.get("log", "")) != "":
			_upload_log(str(staged_content["log"]))

		_upload_staging_root = str(staged_content.get("temp_root", ""))
		upload_path = str(staged_content.get("path", upload_path))
		if bool(staged_content.get("is_temp", false)) and _upload_staging_root != "":
			_upload_temp_paths.append(_upload_staging_root)

	var preview_disk_path := ""
	var preview_api_path := ""
	var preview_prepared: Dictionary = {
		"is_temp": false,
		"created_new_dir": false,
		"warning": "",
	}

	if preview_path != "":
		if upload_path != "" and UploadPaths.is_inside_folder(preview_path, upload_path):
			_fail_upload(
				"Preview image must be outside the content folder.\n"
				+ "Choose a preview file that is not inside the folder you upload."
			)
			return false

		var preview_native := UploadPaths.to_steam_path(preview_path)
		var direct_preview_bytes: int = 0
		if FileAccess.file_exists(preview_native):
			direct_preview_bytes = FileAccess.get_file_as_bytes(preview_native).size()

		if (
			not UploadPaths.is_steam_library_path(preview_native)
			and direct_preview_bytes >= 16
			and direct_preview_bytes <= UploadPaths.MAX_PREVIEW_BYTES
			and (upload_path == "" or not UploadPaths.is_inside_folder(preview_native, upload_path))
		):
			preview_disk_path = preview_native
			_upload_log(
				"Using preview file directly (%d bytes): %s" % [direct_preview_bytes, preview_disk_path]
			)
		else:
			var preview_stage_parent := UploadPaths.staging_parent_for_source(preview_native)
			preview_prepared = WorkshopPreview.prepare_for_upload(preview_path, preview_stage_parent)
			var preview_warning := str(preview_prepared.get("warning", ""))
			if preview_warning.contains("Could not create") or preview_warning.contains("not found"):
				_fail_upload(preview_warning)
				return false
			if preview_warning != "":
				_upload_log(preview_warning)
			preview_disk_path = UploadPaths.to_steam_path(str(preview_prepared.get("path", preview_path)))

		if not FileAccess.file_exists(preview_disk_path):
			_fail_upload("Staged preview file is missing: " + preview_disk_path)
			return false

		var preview_bytes: int = FileAccess.get_file_as_bytes(preview_disk_path).size()
		if preview_bytes < 16:
			_fail_upload(
				"Preview image is too small for Steam (%d bytes; minimum 16)." % preview_bytes
			)
			return false

		if upload_path != "" and UploadPaths.is_inside_folder(preview_disk_path, upload_path):
			_fail_upload("Preview must not be inside the workshop content folder.")
			return false

		preview_api_path = UploadPaths.to_steam_upload_path(preview_disk_path)
	elif preview_path == "":
		_upload_log("No preview image.")

	if upload_path != "":
		var content_api_path := UploadPaths.to_steam_upload_path(upload_path)
		_last_upload_content_path = content_api_path
		var file_count := UploadPaths.count_files_recursive(upload_path)
		var total_bytes := UploadPaths.folder_size_bytes(upload_path)
		_upload_log(
			"Setting content folder (%d files, %.1f MB): %s"
			% [file_count, float(total_bytes) / (1024.0 * 1024.0), content_api_path]
		)
		if not Steam.setItemContent(_ugc_update_handle, content_api_path):
			_fail_upload("Steam rejected the content folder path.")
			return false
		for _i in range(8):
			Steam.run_callbacks()
	elif upload_path == "":
		_upload_log("No content folder specified.")

	if preview_api_path != "":
		_last_upload_preview_path = preview_api_path
		_upload_log(
			"Setting preview image (%d bytes): %s"
			% [FileAccess.get_file_as_bytes(preview_disk_path).size(), preview_api_path]
		)
		if not Steam.setItemPreview(_ugc_update_handle, preview_api_path):
			_fail_upload("Steam rejected the preview image path.")
			return false
		if bool(preview_prepared.get("is_temp", false)) and bool(preview_prepared.get("created_new_dir", false)):
			var preview_parent := UploadPaths.to_steam_path(preview_disk_path.get_base_dir())
			if preview_parent not in _upload_temp_paths:
				_upload_temp_paths.append(preview_parent)
		for _i in range(8):
			Steam.run_callbacks()

	_upload_log("Submitting update to Steam servers…")
	call_deferred("_submit_item_update_deferred", change_notes)
	return true


func _submit_item_update_deferred(change_notes: String) -> void:
	if not _is_valid_ugc_update_handle(_ugc_update_handle):
		_fail_upload("Steam update handle became invalid before submit.")
		return
	for _i in range(24):
		Steam.run_callbacks()
	var tree := get_tree()
	if tree:
		_upload_log("Waiting briefly so Steam can read staged files…")
		tree.create_timer(1.0).timeout.connect(
			func() -> void: _finish_submit_item_update(change_notes),
			CONNECT_ONE_SHOT
		)
	else:
		_finish_submit_item_update(change_notes)


func _finish_submit_item_update(change_notes: String) -> void:
	if not upload_in_progress or not _is_valid_ugc_update_handle(_ugc_update_handle):
		return
	for _i in range(12):
		Steam.run_callbacks()
	_upload_log("Sending update request to Steam…")
	Steam.submitItemUpdate(_ugc_update_handle, change_notes)


func _parse_workshop_tags(tags_csv: String) -> PackedStringArray:
	var tags := PackedStringArray()
	for part in tags_csv.split(","):
		var tag := str(part).strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	return tags


func _fail_upload(message: String) -> void:
	AppLogger.error(message)
	var failed_id := _upload_file_id
	_cleanup_upload_temp_paths()
	upload_in_progress = false
	_upload_file_id = -1
	_ugc_update_handle = -1
	workshop_upload_completed.emit(Steam.RESULT_FAIL, failed_id, false)


func _cleanup_upload_temp_paths() -> void:
	for path in _upload_temp_paths:
		TempFolder.remove_temp_path(path)
	_upload_temp_paths.clear()


func get_upload_progress() -> Dictionary:
	if not _is_valid_ugc_update_handle(_ugc_update_handle):
		return {}
	return Steam.getItemUpdateProgress(_ugc_update_handle)

var _ugc_request_handle: int = -1
var _page_number: int = 1
var _ugc_query_phase: int = UGC_QUERY_NONE
var _details_ids_queue: PackedInt64Array = PackedInt64Array()
var _details_offset: int = 0


func refresh_workshop_items() -> void:
	if not is_initialized:
		AppLogger.error("Could not refresh workshop items, Steam not initialized!")
		return
	if _ugc_request_handle != -1:
		AppLogger.error("Could not refresh workshop items, request already in progress!")
		return
	for draft_id in UgcDraftStore.get_file_ids_for_app(app_id):
		var id := int(draft_id)
		if id > 0 and not UgcItemRegistry.is_removed(app_id, id):
			UgcItemRegistry.add(app_id, id)

	ugc_items.clear()
	_page_number = 1
	_ugc_query_phase = UGC_QUERY_PUBLISHED
	_start_published_query(1)


func query_published_items(_page: int = 1) -> void:
	refresh_workshop_items()


func _start_published_query(page: int) -> void:
	var list := Steam.UserUGCList.USER_UGC_LIST_PUBLISHED
	var type := Steam.UGCMatchingUGCType.UGC_MATCHING_UGC_TYPE_ITEMS
	var sort := Steam.UserUGCListSortOrder.USER_UGC_LIST_SORT_ORDER_CREATION_ORDER_DESC

	_ugc_request_handle = Steam.createQueryUserUGCRequest(
		get_user_steam_id(),
		list, type, sort,
		app_id, app_id, page
	)
	Steam.setReturnLongDescription(_ugc_request_handle, true)
	Steam.sendQueryUGCRequest(_ugc_request_handle)


func _begin_details_query_for_known() -> void:
	var known := UgcItemRegistry.get_ids_for_app(app_id)
	var missing := PackedInt64Array()
	for file_id in known:
		if not ugc_items.has(file_id):
			missing.append(file_id)

	if missing.is_empty():
		_ugc_query_phase = UGC_QUERY_NONE
		steamworks_ugc_items_retrieved.emit()
		return

	_details_ids_queue = missing
	_details_offset = 0
	_ugc_query_phase = UGC_QUERY_DETAILS
	_send_details_query_batch()


func _send_details_query_batch() -> void:
	if _ugc_request_handle != -1:
		return

	var batch: Array = []
	var end := mini(_details_offset + 50, _details_ids_queue.size())
	for i in range(_details_offset, end):
		batch.append(_details_ids_queue[i])
	_details_offset = end

	if batch.is_empty():
		_ugc_query_phase = UGC_QUERY_NONE
		steamworks_ugc_items_retrieved.emit()
		return

	_ugc_request_handle = Steam.createQueryUGCDetailsRequest(batch)
	Steam.setReturnLongDescription(_ugc_request_handle, true)
	Steam.sendQueryUGCRequest(_ugc_request_handle)


func _fetch_ugc_details_for_ids(file_ids: PackedInt64Array) -> void:
	if not is_initialized or file_ids.is_empty():
		return
	if _ugc_request_handle != -1:
		return

	_details_ids_queue = file_ids
	_details_offset = 0
	_ugc_query_phase = UGC_QUERY_DETAILS
	_send_details_query_batch()


func _make_stub_ugc_item(file_id: int) -> Dictionary:
	return {
		"result": Steam.RESULT_OK,
		"file_id": file_id,
		"file_type": Steam.WORKSHOP_FILE_TYPE_COMMUNITY,
		"creator_app_id": app_id,
		"consumer_app_id": app_id,
		"title": "New Workshop Item",
		"description": "",
		"steam_id_owner": get_user_steam_id(),
		"time_created": 0,
		"time_updated": 0,
		"time_added_to_user_list": 0,
		"visibility": 0,
		"banned": false,
		"accepted_for_use": false,
		"tags_truncated": false,
		"tags": "",
		"handle_file": 0,
		"handle_preview_file": 0,
		"file_name": "",
		"file_size": 0,
		"preview_file_size": 0,
		"url": "",
		"votes_up": 0,
		"votes_down": 0,
		"score": 0.0,
		"num_children": 0,
		"total_files_size": 0,
		"preview_url": "",
	}


func _normalize_ugc_query_item(item: Dictionary) -> Dictionary:
	item["file_id"] = int(item.get("file_id", 0))
	for key in [
		"time_created",
		"time_updated",
		"time_added_to_user_list",
		"creator_app_id",
		"consumer_app_id",
		"steam_id_owner",
	]:
		if item.has(key):
			item[key] = int(item[key])
	return item


func fetch_queried_ugc_items(count: int):
	for i in range(count):
		var item: Dictionary = Steam.getQueryUGCResult(_ugc_request_handle, i)
		item = _normalize_ugc_query_item(item)
		var file_id := int(item.get("file_id", 0))
		if file_id <= 0:
			continue
		if UgcItemRegistry.is_removed(app_id, file_id):
			continue
		if int(item.get("result", Steam.RESULT_OK)) != Steam.RESULT_OK:
			continue
		if not ugc_item_belongs_to_app(item, app_id):
			continue
		ugc_items.set(file_id, item)
		UgcItemRegistry.add(app_id, file_id)

		# Seems to always be 0 for Binding of Isaac.
		# var num_kv_tags = Steam.getQueryUGCNumKeyValueTags(_ugc_request_handle, i)
		# print("Entry has " + str(num_kv_tags) + " key/value tags")
		
		var preview_url = Steam.getQueryUGCPreviewURL(_ugc_request_handle, i)
		item["preview_url"] = preview_url
		item["tags"] = _merge_ugc_tags(item, _ugc_request_handle, i)


func _merge_ugc_tags(item: Dictionary, query_handle: int, index: int) -> String:
	var tag_set: Dictionary = {}
	for part in str(item.get("tags", "")).split(","):
		var tag := str(part).strip_edges()
		if not tag.is_empty():
			tag_set[tag] = true

	var num_kv: int = int(Steam.getQueryUGCNumKeyValueTags(query_handle, index))
	for j in range(num_kv):
		var kv: Dictionary = Steam.getQueryUGCKeyValueTag(query_handle, index, j)
		if not kv.get("success", false):
			continue
		for key_name in ["value", "key"]:
			var entry := str(kv.get(key_name, "")).strip_edges()
			if not entry.is_empty():
				tag_set[entry] = true

	if tag_set.is_empty():
		return str(item.get("tags", ""))
	return ",".join(tag_set.keys())

#
# Signal Callbacks
#

func on_current_stats_received():
	AppLogger.info("[STEAM] Current stats received")
	emit_signal("current_stats_received")
	
func on_item_created(result: int, file_id: int, accept_tos: bool) -> void:
	AppLogger.info(
		"[STEAM] Item created: " + str(file_id) + " (result: " + SteamResult.stringify(result) + ")"
	)
	emit_signal("item_created", result, file_id, accept_tos)

	if accept_tos:
		open_tos_url()

	if result == Steam.RESULT_OK and file_id > 0:
		UgcItemRegistry.add(app_id, file_id)
		if not ugc_items.has(file_id):
			ugc_items[file_id] = _make_stub_ugc_item(file_id)
		steamworks_ugc_items_retrieved.emit()
		_fetch_ugc_details_for_ids(PackedInt64Array([file_id]))
	
func on_item_updated(result: int, need_to_accept_tos: bool, updated_file_id: int = 0) -> void:
	var file_id := _upload_file_id
	if updated_file_id > 0:
		file_id = updated_file_id

	if upload_in_progress and file_id <= 0:
		AppLogger.warning("[STEAM] item_updated without active upload file id.")
		return

	var was_upload := upload_in_progress
	upload_in_progress = false
	_ugc_update_handle = -1

	if result == Steam.RESULT_OK:
		_upload_log("[STEAM] Item %d updated successfully." % file_id)
		_cleanup_upload_temp_paths()
		_upload_file_id = -1
		refresh_workshop_items()
	elif (
		result == Steam.RESULT_FILE_NOT_FOUND
		and was_upload
		and _last_upload_preview_path != ""
		and not _upload_retry_without_preview
	):
		var hint := _upload_error_hint(result)
		_upload_log("[STEAM] Item %d update failed: %s" % [file_id, hint])
		_log_upload_path_diagnostics()
		_upload_log("Automatic retry without preview image (content only)…")
		_upload_retry_without_preview = true
		var retry_params := _upload_last_params.duplicate(true)
		retry_params["preview_path"] = ""
		retry_params["retry_without_preview"] = true
		_upload_file_id = file_id
		call_deferred("_retry_workshop_upload", file_id, retry_params, _upload_last_change_notes)
		return
	else:
		var hint := _upload_error_hint(result)
		_upload_log("[STEAM] Item %d update failed: %s" % [file_id, hint])
		if result == Steam.RESULT_FILE_NOT_FOUND:
			_log_upload_path_diagnostics()
			if _upload_was_metadata_only:
				_upload_log(
					"Metadata-only upload failed — this is NOT a file-path problem. "
					+ "Steam cannot update workshop item %d for app %d. "
					% [file_id, app_id]
				)
				_upload_log(
					"Create a NEW Workshop item (Create UGC Item on the main screen), "
					+ "accept the Workshop agreement in the Steam overlay, then upload again."
				)
			else:
				_upload_log(
					"Staging folders were kept on disk for inspection. "
					+ "Try a smaller test upload or D:\\Mods\\ for the package."
				)
		else:
			_cleanup_upload_temp_paths()
		_upload_file_id = -1

	if need_to_accept_tos:
		AppLogger.warning("You must accept the Steam Workshop legal agreement in the overlay.")
		open_tos_url()

	if was_upload:
		workshop_upload_completed.emit(result, file_id, need_to_accept_tos)

	emit_signal("item_updated", file_id)


func _retry_workshop_upload(file_id: int, params: Dictionary, change_notes: String) -> void:
	upload_in_progress = false
	if not update_workshop_item(file_id, params, change_notes):
		workshop_upload_completed.emit(Steam.RESULT_FAIL, file_id, false)


func _log_upload_path_diagnostics() -> void:
	if _last_upload_content_path != "":
		_upload_log("Content folder used: " + _last_upload_content_path)
	if _last_upload_preview_path != "":
		_upload_log("Preview file used: " + _last_upload_preview_path)


func _validate_workshop_item_before_upload(file_id: int, consumer_app_id: int) -> String:
	if file_id <= 0:
		return "Invalid workshop item id."
	if consumer_app_id <= 0:
		return "Could not determine the Steam App ID for this workshop item."

	if not ugc_items.has(file_id):
		_upload_log(
			"Workshop item %d is not in the local list — refreshing details from Steam…"
			% file_id
		)
		_fetch_ugc_details_for_ids(PackedInt64Array([file_id]))
		return ""

	var item: Dictionary = ugc_items[file_id]
	var creator := int(item.get("creator_app_id", 0))
	var consumer := int(item.get("consumer_app_id", 0))
	_upload_log(
		"Item %d: file_type=%s visibility=%s banned=%s"
		% [
			file_id,
			str(item.get("file_type", "?")),
			str(item.get("visibility", "?")),
			str(item.get("banned", false)),
		]
	)
	if creator > 0 and creator != consumer_app_id:
		_upload_log(
			"Note: creator_app_id=%d differs from selected app %d."
			% [creator, consumer_app_id]
		)
	if consumer > 0 and consumer != consumer_app_id:
		return (
			"Workshop item %d belongs to app %d, but you selected app %d.\n"
			+ "Switch to the correct game on the main screen or create a new item."
			% [file_id, consumer, consumer_app_id]
		)
	if bool(item.get("banned", false)):
		return "This Workshop item is banned and cannot be updated."
	return ""


func _upload_error_hint(result: int) -> String:
	var result_name: String = SteamResult.stringify(result)
	if result == Steam.RESULT_FILE_NOT_FOUND and _upload_was_metadata_only:
		return (
			"%s — Steam cannot find or update workshop item %d (even title/description only). "
			+ "The item may be invalid for TurretGirls, or Workshop updates are disabled. "
			+ "Create a NEW item via Create UGC Item."
		) % [result_name, _upload_file_id]
	match result:
		Steam.RESULT_LIMIT_EXCEEDED:
			return "%s — preview must be under 1 MB, or Steam Cloud is full." % result_name
		Steam.RESULT_INVALID_PARAM:
			return "%s — check Workshop is enabled for this game in Steamworks partner settings." % result_name
		Steam.RESULT_FILE_NOT_FOUND:
			return (
				"%s — Steam could not read preview or content. "
				+ "If title/description upload works but files fail, the game may block large "
				+ "Workshop uploads (~350 MB) or file transfer is disabled — use D:\\Mods\\ or Steam client."
			) % result_name
		_:
			return result_name
	
func on_item_deleted(result: int, file_id: int) -> void:
	AppLogger.info("[STEAM] Item deleted: " + str(file_id) + " (result: " + SteamResult.stringify(result) + ")")
	if result == Steam.RESULT_OK or result == Steam.RESULT_ITEM_DELETED:
		UgcItemRegistry.mark_removed(app_id, file_id)
		UgcDraftStore.erase_draft(file_id)
		ugc_items.erase(file_id)
		if int(current_ugc_item.get("file_id", -1)) == file_id:
			current_ugc_item = {}
		_upload_log("Workshop item %d removed locally (draft + registry)." % file_id)
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
	
func on_ugc_query_completed(
	handle: int,
	result: int,
	results_returned: int,
	total_matching: int,
	cached: bool
) -> void:
	AppLogger.info(
		"[STEAM] UGC query completed (result: "
		+ SteamResult.stringify(result)
		+ "), got "
		+ str(results_returned)
		+ " items"
	)
	emit_signal("ugc_query_completed", handle, result, results_returned, total_matching, cached)

	if result == Steam.RESULT_OK and results_returned > 0:
		fetch_queried_ugc_items(results_returned)
	elif result != Steam.RESULT_OK:
		AppLogger.error("Couldn't get UGC: " + SteamResult.stringify(result))

	_ugc_request_handle = -1

	if _ugc_query_phase == UGC_QUERY_PUBLISHED:
		if result == Steam.RESULT_OK and results_returned == 50:
			_page_number += 1
			_start_published_query(_page_number)
		else:
			_begin_details_query_for_known()
	elif _ugc_query_phase == UGC_QUERY_DETAILS:
		if _details_offset < _details_ids_queue.size():
			_send_details_query_batch()
		else:
			_ugc_query_phase = UGC_QUERY_NONE
			steamworks_ugc_items_retrieved.emit()
	
func on_dlc_installed(_app_id:int):
	AppLogger.info("[STEAM] DLC installed: " + str(_app_id))
	emit_signal("dlc_installed", _app_id)
	
func on_user_subscribed_items_list_changed(_app_id:int):
	AppLogger.info("[STEAM] User subscribed items list changed")
	emit_signal("user_subscribed_items_list_changed", _app_id)

var _last_overlay_log_state: int = -1


func on_overlay_toggled(active: bool, user_initiated: bool, _app_id: int) -> void:
	var state_key := int(active) | (int(user_initiated) << 1)
	if state_key != _last_overlay_log_state:
		_last_overlay_log_state = state_key
		AppLogger.info(
			"[STEAM] Overlay toggled: " + str(active) + " (user? " + str(user_initiated) + ")"
		)
	overlay_toggled.emit(active, user_initiated)
