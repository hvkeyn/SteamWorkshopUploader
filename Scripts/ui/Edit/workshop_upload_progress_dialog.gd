extends Window

signal upload_finished(result: int, file_id: int, need_accept_tos: bool)

@onready var _status_label: Label = %StatusLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _detail_label: Label = %DetailLabel
@onready var _log_scroll: ScrollContainer = $Margin/VBox/BodySplit/LogScroll
@onready var _log_view: RichTextLabel = %LogView
@onready var _result_panel: PanelContainer = %ResultPanel  # Inside BodySplit, below log.
@onready var _result_label: Label = %ResultLabel
@onready var _close_button: Button = %CloseButton
@onready var _open_workshop_button: Button = %OpenWorkshopButton
@onready var _copy_log_button: Button = %CopyLogButton

var _file_id: int = -1
var _waiting_steam: bool = false
var _finished: bool = false
var _pending_preamble: PackedStringArray = PackedStringArray()


func _ready() -> void:
	title = "Workshop upload"
	size = Vector2i(560, 440)
	min_size = Vector2i(480, 360)
	unresizable = false
	close_requested.connect(_on_close_requested)
	_close_button.pressed.connect(_on_close_pressed)
	_open_workshop_button.pressed.connect(_on_open_workshop_pressed)
	_copy_log_button.pressed.connect(_on_copy_log_pressed)
	_result_panel.visible = false
	_open_workshop_button.visible = false

	if Steamworks.workshop_upload_log.is_connected(_on_upload_log):
		Steamworks.workshop_upload_log.disconnect(_on_upload_log)
	Steamworks.workshop_upload_log.connect(_on_upload_log)

	if _file_id > 0:
		_apply_open_state()


func _exit_tree() -> void:
	if Steamworks.workshop_upload_log.is_connected(_on_upload_log):
		Steamworks.workshop_upload_log.disconnect(_on_upload_log)


func add_log(line: String) -> void:
	if _log_view == null:
		_pending_preamble.append(line)
		return
	_append_log(line)


func open_for_upload(file_id: int, preamble: PackedStringArray = PackedStringArray()) -> void:
	_file_id = file_id
	_pending_preamble = preamble.duplicate()
	_waiting_steam = false
	_finished = false

	if Steamworks.workshop_upload_completed.is_connected(_on_steam_upload_completed):
		Steamworks.workshop_upload_completed.disconnect(_on_steam_upload_completed)
	Steamworks.workshop_upload_completed.connect(_on_steam_upload_completed, CONNECT_ONE_SHOT)

	var host := get_tree().root
	if host and get_parent() != host:
		host.add_child(self)

	if is_node_ready():
		_apply_open_state()
	else:
		call_deferred("_apply_open_state")


func _apply_open_state() -> void:
	_progress_bar.indeterminate = false
	_progress_bar.value = 0.0
	_status_label.text = "Preparing upload…"
	_detail_label.text = ""
	_log_view.clear()
	_result_panel.visible = false
	_open_workshop_button.visible = false
	_close_button.disabled = true
	_close_button.text = "Close"

	for line in _pending_preamble:
		_append_log(line)
	_pending_preamble.clear()

	call_deferred("_scroll_log_to_end")
	popup_centered()
	grab_focus()


func mark_waiting_for_steam() -> void:
	_waiting_steam = true
	if _status_label:
		_status_label.text = "Uploading to Steam…"
	_append_log("Waiting for Steam servers…")


func fail_before_submit(message: String) -> void:
	_waiting_steam = false
	_finished = true
	if _progress_bar:
		_progress_bar.indeterminate = false
		_progress_bar.value = 0.0
	if _status_label:
		_status_label.text = "Upload cancelled"
	_append_log("ERROR: " + message)
	_show_result(false, message)
	if _close_button:
		_close_button.disabled = false
	if Steamworks.workshop_upload_completed.is_connected(_on_steam_upload_completed):
		Steamworks.workshop_upload_completed.disconnect(_on_steam_upload_completed)
	upload_finished.emit(Steam.RESULT_FAIL, _file_id, false)


func _process(_delta: float) -> void:
	if not _waiting_steam or _finished or _progress_bar == null:
		return
	if not Steamworks.is_upload_in_progress():
		return

	var progress: Dictionary = Steamworks.get_upload_progress()
	if progress.is_empty():
		return

	var status: int = int(progress.get("status", 0))
	var processed: int = int(progress.get("processed", 0))
	var total: int = int(progress.get("total", 0))

	_status_label.text = _status_name(status)

	if total > 0:
		_progress_bar.indeterminate = false
		_progress_bar.value = clampf(float(processed) / float(total) * 100.0, 0.0, 100.0)
		_detail_label.text = "%s / %s" % [_format_bytes(processed), _format_bytes(total)]
	elif status >= Steam.ITEM_UPDATE_STATUS_COMMITTING_CHANGES:
		_progress_bar.indeterminate = false
		_progress_bar.value = 100.0
		_detail_label.text = "Committing changes…"
	else:
		_progress_bar.indeterminate = true
		_detail_label.text = ""


func _on_upload_log(line: String) -> void:
	_append_log(line)


func _on_steam_upload_completed(result: int, file_id: int, need_to_accept_tos: bool) -> void:
	_waiting_steam = false
	_finished = true
	if _progress_bar:
		_progress_bar.indeterminate = false

	if result == Steam.RESULT_OK and not need_to_accept_tos:
		if _progress_bar:
			_progress_bar.value = 100.0
		_status_label.text = "Upload complete"
		var success_msg := "Workshop item %d was updated successfully." % file_id
		if Steamworks.was_last_upload_metadata_only():
			success_msg += (
				"\n\nOnly title/description were sent (no files or preview). "
				+ "Submit again without skipping content to upload the mod."
			)
		_show_result(true, success_msg)
		_open_workshop_button.visible = true
		_append_log("SUCCESS: Steam accepted the update.")
	elif need_to_accept_tos:
		if _progress_bar:
			_progress_bar.value = 0.0
		_status_label.text = "Legal agreement required"
		_show_result(
			false,
			"Steam requires you to accept the Workshop legal agreement in the Steam overlay, then submit again."
		)
		_append_log("ACTION REQUIRED: accept Workshop TOS in Steam overlay.")
	else:
		if _progress_bar:
			_progress_bar.value = 0.0
		_status_label.text = "Upload failed"
		var hint: String = _result_message_for_code(result)
		_show_result(false, hint)
		_append_log("FAILED (%s). Details below." % SteamResult.stringify(result))

	if _close_button:
		_close_button.disabled = false
	call_deferred("_scroll_log_to_end")
	upload_finished.emit(result, file_id, need_to_accept_tos)


func _show_result(success: bool, message: String) -> void:
	if _result_panel != null:
		_result_panel.visible = true
	if _result_label == null:
		# Fallback: broken scene tree — still show message in the log.
		_append_log(message)
		return
	_result_label.text = message
	if success:
		_result_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	else:
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))


func _append_log(line: String) -> void:
	if _log_view == null:
		_pending_preamble.append(line)
		return
	var stamp: String = Time.get_time_string_from_system()
	_log_view.append_text("[%s] %s\n" % [stamp, line])
	_log_view.custom_minimum_size.y = maxf(120.0, float(_log_view.get_content_height()) + 8.0)
	call_deferred("_scroll_log_to_end")


func _scroll_log_to_end() -> void:
	if _log_scroll == null:
		return
	call_deferred("_apply_log_scroll")


func _apply_log_scroll() -> void:
	if _log_scroll == null:
		return
	var vbar := _log_scroll.get_v_scroll_bar()
	if vbar:
		vbar.value = vbar.max_value


func _status_name(status: int) -> String:
	match status:
		Steam.ITEM_UPDATE_STATUS_PREPARING_CONFIG:
			return "Preparing configuration…"
		Steam.ITEM_UPDATE_STATUS_PREPARING_CONTENT:
			return "Preparing content files…"
		Steam.ITEM_UPDATE_STATUS_UPLOADING_CONTENT:
			return "Uploading content…"
		Steam.ITEM_UPDATE_STATUS_UPLOADING_PREVIEW_FILE:
			return "Uploading preview image…"
		Steam.ITEM_UPDATE_STATUS_COMMITTING_CHANGES:
			return "Committing to Steam…"
		_:
			return "Processing…"


func _result_message_for_code(result: int) -> String:
	match result:
		Steam.RESULT_LIMIT_EXCEEDED:
			return "Preview must be under 1 MB, or Steam Cloud is full."
		Steam.RESULT_INVALID_PARAM:
			return (
				"Steam rejected parameters. Workshop may be disabled for this game, "
				+ "or the preview/content format is not accepted."
			)
		Steam.RESULT_FILE_NOT_FOUND:
			return (
				"Steam could not read the content or preview paths. "
				+ "Create a new Workshop item if this persists, accept the Workshop agreement in the Steam overlay, "
				+ "then try again. For large mods (~350 MB), use the Steam client."
			)
		_:
			return "Steam error: %s" % SteamResult.stringify(result)


func _format_bytes(amount: int) -> String:
	if amount < 1024:
		return "%d B" % amount
	if amount < 1024 * 1024:
		return "%.1f KB" % (float(amount) / 1024.0)
	return "%.2f MB" % (float(amount) / (1024.0 * 1024.0))


func _on_close_requested() -> void:
	if not _finished:
		return
	queue_free()


func _on_close_pressed() -> void:
	queue_free()


func _on_open_workshop_pressed() -> void:
	if _file_id > 0:
		Steamworks.open_url(
			"https://steamcommunity.com/sharedfiles/filedetails/?id=%d" % _file_id
		)


func _on_copy_log_pressed() -> void:
	var text := get_full_log_text()
	if text.is_empty():
		return
	DisplayServer.clipboard_set(text)
	if _detail_label:
		_detail_label.text = "Log copied to clipboard."


func get_full_log_text() -> String:
	if _log_view == null:
		return "\n".join(_pending_preamble)
	return _log_view.get_parsed_text()
