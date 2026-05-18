extends Node

## Downloads the public Steam AppID CSV in the background (once per week).

signal master_list_ready(count: int)

const MasterList = preload("res://Scripts/steam_master_app_list.gd")

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	if MasterList.ensure_loaded() and not MasterList.is_cache_stale():
		master_list_ready.emit(MasterList.get_lookup().size())
		return

	_download()


func _download() -> void:
	AppLogger.info("Downloading Steam app name database (CSV)...")
	var headers := PackedStringArray(["User-Agent: SteamWorkshopUploader/1.0"])
	_http.request(MasterList.REMOTE_CSV_URL, headers)


func stop() -> void:
	if _http:
		_http.cancel_request()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		AppLogger.error("Failed to download Steam app name database (HTTP %d)." % response_code)
		master_list_ready.emit(MasterList.get_lookup().size())
		return

	var count := MasterList.apply_remote_csv(body.get_string_from_utf8())
	if count > 0:
		AppLogger.info("Steam app name database ready (%d entries)." % count)
	else:
		AppLogger.warning("Steam app name database unavailable; using installed-game names only.")
	master_list_ready.emit(count)
