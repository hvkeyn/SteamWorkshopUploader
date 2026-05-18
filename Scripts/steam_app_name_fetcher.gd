extends Node

## Fallback: fetch individual app names from the store API when missing from the master list.

const Scanner = preload("res://Scripts/steam_library_scanner.gd")

signal names_updated

const STORE_API := "https://store.steampowered.com/api/appdetails"
const REQUEST_INTERVAL_SEC := 0.15

var _queue: Array[int] = []
var _cache: Dictionary = {}
var _http: HTTPRequest
var _cooldown: float = 0.0
var _active: bool = false
var _shutting_down: bool = false


func _ready() -> void:
	_cache = Scanner.load_name_cache()
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func fetch_missing(app_ids: Array) -> void:
	if _shutting_down:
		return
	for app_id in app_ids:
		var id := int(app_id)
		if _cache.has(str(id)) or id in _queue:
			continue
		_queue.append(id)
	if not _queue.is_empty():
		_active = true


func prioritize(app_ids: Array) -> void:
	if _shutting_down or app_ids.is_empty():
		return
	var prioritized: Array[int] = []
	for app_id in app_ids:
		var id := int(app_id)
		if id in _queue:
			prioritized.append(id)
	for id in _queue:
		if id not in prioritized:
			prioritized.append(id)
	_queue = prioritized
	_active = true


func stop() -> void:
	_shutting_down = true
	_active = false
	_queue.clear()
	if _http:
		_http.cancel_request()


func get_cached_name(app_id: int) -> String:
	return str(_cache.get(str(app_id), ""))


func _process(delta: float) -> void:
	if _shutting_down or not _active or _queue.is_empty():
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return

	var app_id: int = _queue.pop_front()
	var url := "%s?appids=%d&filters=basic" % [STORE_API, app_id]
	var headers := PackedStringArray([
		"User-Agent: SteamWorkshopUploader/1.0",
		"Accept: application/json",
	])
	_http.request(url, headers)
	_cooldown = REQUEST_INTERVAL_SEC


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _shutting_down:
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			for app_id_str in parsed.keys():
				var entry: Variant = parsed[app_id_str]
				if not entry is Dictionary or not entry.get("success", false):
					continue
				var data: Variant = entry.get("data", {})
				if not data is Dictionary:
					continue
				var name := str(data.get("name", ""))
				if not name.is_empty():
					_cache[app_id_str] = name
		Scanner.save_name_cache(_cache)
		names_updated.emit()

	if _queue.is_empty() and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_active = false
