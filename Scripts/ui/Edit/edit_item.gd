extends Control

const DraftStore = preload("res://Scripts/ugc_draft_store.gd")
const UploadProgressScene = preload("res://Scenes/ui/WorkshopUploadProgress.tscn")
const UploadPaths = preload("res://Scripts/workshop_upload_paths.gd")

var _save_draft_queued: bool = false
var _upload_dialog: Window = null
var _suppress_draft_save: bool = false
var _autosave_connected: bool = false


func _ready() -> void:
	add_to_group("ugc_edit_screen")
	call_deferred("_load_editor_state")


func _get_file_id() -> int:
	return int(Steamworks.current_ugc_item.get("file_id", -1))


func _load_editor_state() -> void:
	_suppress_draft_save = true
	_save_draft_queued = false

	var file_id := _get_file_id()
	var draft: Dictionary = DraftStore.get_draft(file_id)

	reset_fields()
	if file_id > 0 and not _is_draft_empty(draft):
		_apply_draft(draft)

	_suppress_draft_save = false
	if not _autosave_connected:
		_connect_draft_autosave()
		_autosave_connected = true


func _connect_draft_autosave() -> void:
	%LineEditTitle.text_changed.connect(_on_draft_field_changed)
	%TextEditDescription.text_changed.connect(_on_draft_field_changed)
	%LineEditChangeNotes.text_changed.connect(_on_draft_field_changed)
	%OptionButtonVisibility.item_selected.connect(func(_i): _queue_save_draft())
	%CheckBoxDescriptionShouldUpdate.toggled.connect(func(_t): _queue_save_draft())
	if has_node("%ButtonBrowseFiles"):
		%ButtonBrowseFiles.target_path_changed.connect(func(_p): _queue_save_draft())
	%ButtonSelectPreviewImage.preview_changed.connect(func(_p): _queue_save_draft())
	%HBoxTagList.tags_changed.connect(_on_draft_field_changed)
	var tabs := $VBoxContainer/OuterMargin/Panel/Margin/VBox/TabContainer as TabContainer
	if tabs:
		tabs.tab_changed.connect(func(_t): _queue_save_draft())


func _on_draft_field_changed(_arg: Variant = null) -> void:
	_queue_save_draft()


func _queue_save_draft() -> void:
	if _suppress_draft_save:
		return
	if _save_draft_queued:
		return
	_save_draft_queued = true
	call_deferred("_save_draft")


func save_draft_now() -> void:
	if _suppress_draft_save:
		return
	_save_draft_queued = false
	_save_draft()


func _save_draft() -> void:
	_save_draft_queued = false
	if _suppress_draft_save:
		return
	var file_id := _get_file_id()
	if file_id <= 0:
		return
	var payload := {
		"title": %LineEditTitle.text,
		"description": %TextEditDescription.text,
		"visibility": %OptionButtonVisibility.get_item_id(%OptionButtonVisibility.selected),
		"description_should_update": %CheckBoxDescriptionShouldUpdate.button_pressed,
		"tags": %HBoxTagList.current_tags.duplicate(),
		"preview_path": %ButtonSelectPreviewImage.preview_image_path,
		"upload_path": %ButtonBrowseFiles.upload_target_path if has_node("%ButtonBrowseFiles") else "",
		"change_notes": %LineEditChangeNotes.text,
	}
	DraftStore.set_draft(file_id, payload)


func _is_draft_empty(draft: Dictionary) -> bool:
	if draft.is_empty():
		return true
	if str(draft.get("title", "")).strip_edges() != "":
		return false
	if str(draft.get("description", "")).strip_edges() != "":
		return false
	if str(draft.get("change_notes", "")).strip_edges() != "":
		return false
	if str(draft.get("preview_path", "")).strip_edges() != "":
		return false
	if str(draft.get("upload_path", "")).strip_edges() != "":
		return false
	var tags: Variant = draft.get("tags", [])
	if tags is Array and not tags.is_empty():
		return false
	return true


func _apply_draft(draft: Dictionary) -> void:
	if draft.has("title"):
		%LineEditTitle.text = str(draft["title"])
	if draft.has("visibility"):
		var vis_id: int = int(draft["visibility"])
		var vis_idx: int = %OptionButtonVisibility.get_item_index(vis_id)
		if vis_idx >= 0:
			%OptionButtonVisibility.selected = vis_idx
	%CheckBoxDescriptionShouldUpdate.set_block_signals(true)
	if draft.has("description_should_update"):
		%CheckBoxDescriptionShouldUpdate.button_pressed = bool(draft["description_should_update"])
	%TextEditDescription.editable = %CheckBoxDescriptionShouldUpdate.button_pressed
	%CheckBoxDescriptionShouldUpdate.set_block_signals(false)
	if draft.has("description"):
		var desc := str(draft["description"])
		%TextEditDescription.text = desc
		%RichTextDescription.text = desc
	if draft.has("change_notes"):
		%LineEditChangeNotes.text = str(draft["change_notes"])
	if draft.has("tags") and %HBoxTagList.has_method("set_tags"):
		%HBoxTagList.set_tags(draft["tags"] as Array)
	var preview_path := str(draft.get("preview_path", ""))
	if preview_path != "" and FileAccess.file_exists(preview_path):
		%ButtonSelectPreviewImage.preview_image_path = preview_path
		WebImage.load_from_path(preview_path, %SpritePreviewImage)
	var upload_path := str(draft.get("upload_path", ""))
	if upload_path != "" and has_node("%ButtonBrowseFiles"):
		%ButtonBrowseFiles.upload_target_path = upload_path
		if DirAccess.dir_exists_absolute(upload_path):
			%ItemListFiles.on_target_path_changed(upload_path)


func _ugc_unix_time(item: Dictionary, key: String) -> int:
	if item.has(key):
		return int(item[key])
	return 0


func _format_unix_time(unix_time: int) -> String:
	if unix_time <= 0:
		return "—"
	return Time.get_datetime_string_from_unix_time(unix_time, true)


func reset_fields() -> void:
	var file_id: int = Steamworks.current_ugc_item["file_id"]
	var title: String = Steamworks.current_ugc_item["title"]
	var description: String = Steamworks.current_ugc_item["description"]

	var visibility: int = Steamworks.current_ugc_item["visibility"]

	var score: float = Steamworks.current_ugc_item["score"]
	var votes_up: int = Steamworks.current_ugc_item["votes_up"]
	var votes_down: int = Steamworks.current_ugc_item["votes_down"]

	var preview_url: String = Steamworks.current_ugc_item["preview_url"]

	var time_created: int = _ugc_unix_time(Steamworks.current_ugc_item, "time_created")
	var time_updated: int = _ugc_unix_time(Steamworks.current_ugc_item, "time_updated")

	var time_created_str: String = _format_unix_time(time_created)
	var time_updated_str: String = _format_unix_time(time_updated)

	var _tags_truncated: bool = Steamworks.current_ugc_item["tags_truncated"]
	var tags: String = Steamworks.current_ugc_item["tags"]
	var _tag_list = tags.split(",")

	var _result: int = Steamworks.current_ugc_item["result"]
	var _file_type: Steam.WorkshopFileType = Steamworks.current_ugc_item["file_type"]
	var _creator_app_id: int = Steamworks.current_ugc_item["creator_app_id"]
	var _consumer_app_id: int = Steamworks.current_ugc_item["consumer_app_id"]
	var _steam_id_owner: int = Steamworks.current_ugc_item["steam_id_owner"]
	var _time_added_to_user_list: int = Steamworks.current_ugc_item["time_added_to_user_list"]
	var _banned: bool = Steamworks.current_ugc_item["banned"]
	var _accepted_for_use: bool = Steamworks.current_ugc_item["accepted_for_use"]
	var _handle_file: int = Steamworks.current_ugc_item["handle_file"]
	var _handle_preview_file: int = Steamworks.current_ugc_item["handle_preview_file"]
	var _file_name: String = Steamworks.current_ugc_item["file_name"]
	var _file_size: int = Steamworks.current_ugc_item["file_size"]
	var _preview_file_size: int = Steamworks.current_ugc_item["preview_file_size"]
	var _url: String = Steamworks.current_ugc_item["url"]
	var _num_children: int = Steamworks.current_ugc_item["num_children"]
	var _total_files_size: int = Steamworks.current_ugc_item["total_files_size"]

	%LabelFileIDValue.text = str(file_id)
	var score_value = str(score) + " (+" + str(votes_up) + "/-" + str(votes_down) + ")"
	%LabelScoreValue.text = score_value
	%LabelFileCreatedValue.text = time_created_str
	%LabelFileUpdatedValue.text = time_updated_str

	%LineEditTitle.text = title
	%OptionButtonVisibility.selected = %OptionButtonVisibility.get_item_index(visibility)

	%TextEditDescription.text = description
	%RichTextDescription.text = description

	load_preview_from_url(preview_url)

	if %HBoxTagList.has_method("configure"):
		%HBoxTagList.configure()


func load_preview_from_url(url: String) -> void:
	if url == "":
		return
	WebImage.load_image_from_url(url, %SpritePreviewImage)


func _on_button_revert_pressed() -> void:
	AppLogger.info("Reverting UGC changes...")
	var file_id := _get_file_id()
	DraftStore.erase_draft(file_id)
	reset_fields()


func get_visiblity() -> Steam.RemoteStoragePublishedFileVisibility:
	return %OptionButtonVisibility.get_item_id(%OptionButtonVisibility.selected)


func _on_button_submit_pressed() -> void:
	var file_id: int = int(Steamworks.current_ugc_item.get("file_id", -1))
	var change_notes: String = %LineEditChangeNotes.text.strip_edges()

	if change_notes.is_empty():
		_show_blocking_error(
			"Fill in \"Change notes\" at the bottom of the editor before submitting."
		)
		return

	_open_upload_dialog(file_id)
	_upload_dialog.add_log("Preparing workshop item %d for upload." % file_id)

	var new_ugc_data: Dictionary = Steamworks.current_ugc_item.duplicate()
	new_ugc_data["title"] = %LineEditTitle.text

	if %CheckBoxDescriptionShouldUpdate.button_pressed:
		new_ugc_data["description"] = %TextEditDescription.text
		_upload_dialog.add_log("Description will be updated (%d chars)." % new_ugc_data["description"].length())
	else:
		new_ugc_data["description"] = ""
		_upload_dialog.add_log("Description update skipped.")

	new_ugc_data["visibility"] = get_visiblity()
	new_ugc_data["tags"] = ",".join(%HBoxTagList.current_tags)

	if %ButtonSelectPreviewImage.preview_image_path != "":
		new_ugc_data["preview_path"] = %ButtonSelectPreviewImage.preview_image_path
		_upload_dialog.add_log("Preview: " + new_ugc_data["preview_path"])
	else:
		new_ugc_data["preview_path"] = ""

	var upload_dir: String = ""
	var base_dir: String = %ButtonBrowseFiles.upload_target_path

	if base_dir == "":
		_upload_dialog.add_log("No content folder selected.")
	elif %CheckBoxExcludeFiles.button_pressed:
		_upload_dialog.add_log("Building filtered file list from: " + base_dir)
		_upload_dialog.add_log("Scanning files (large mods can take a minute)…")
		await get_tree().process_frame

		var stage_parent := ""
		if UploadPaths.is_steam_library_path(base_dir):
			stage_parent = UploadPaths.staging_parent_for_source(base_dir)
		var temp_dir := TempFolder.create_temp_folder(stage_parent)
		if temp_dir.is_empty():
			_upload_dialog.fail_before_submit("Could not create temporary upload folder.")
			return

		var export_data: Dictionary = %ItemListFiles.export_data()
		if export_data.is_empty():
			_upload_dialog.fail_before_submit("Could not build the file list for upload.")
			return

		var relative_paths: PackedStringArray = export_data["relative_paths"]
		var absolute_paths: PackedStringArray = export_data["absolute_paths"]
		var count: int = relative_paths.size()
		_upload_dialog.add_log("Copying %d files to temporary folder…" % count)

		if not TempFolder.copy_files_to_folder(temp_dir, absolute_paths, relative_paths):
			_upload_dialog.fail_before_submit("Failed to copy files to the temporary upload folder.")
			return

		upload_dir = temp_dir
		_upload_dialog.add_log("Temporary content ready: " + temp_dir)
	else:
		upload_dir = base_dir
		_upload_dialog.add_log("Using full folder (no exclusion): " + base_dir)

	new_ugc_data["upload_path"] = upload_dir
	new_ugc_data["metadata_only"] = false

	if upload_dir.is_empty():
		_upload_dialog.fail_before_submit(
			"No content folder selected.\n"
			+ "Use \"Browse Files\" and choose COPY_TO_GAME_FOLDER before submitting."
		)
		return

	if new_ugc_data["preview_path"] == "":
		_upload_dialog.add_log("WARNING: No preview image — Steam page will show a blank thumbnail.")

	if not Steamworks.update_workshop_item(file_id, new_ugc_data, change_notes):
		_upload_dialog.fail_before_submit("Could not start Steam upload. See log above.")
		return

	_upload_dialog.mark_waiting_for_steam()


func _open_upload_dialog(file_id: int) -> void:
	if _upload_dialog != null and is_instance_valid(_upload_dialog):
		_upload_dialog.queue_free()

	_upload_dialog = UploadProgressScene.instantiate()
	_upload_dialog.upload_finished.connect(_on_workshop_upload_completed)
	var host := get_window()
	if host:
		host.add_child(_upload_dialog)
	else:
		add_child(_upload_dialog)
	_upload_dialog.open_for_upload(file_id)
	_set_submit_ui_busy(true)


func _set_submit_ui_busy(busy: bool) -> void:
	var submit := get_node_or_null("%ButtonSubmit") as Button
	var revert := get_node_or_null("%ButtonRevert") as Button
	if submit:
		submit.disabled = busy
		submit.text = "Uploading…" if busy else "Submit Changes"
	if revert:
		revert.disabled = busy


func _on_workshop_upload_completed(result: int, file_id: int, need_to_accept_tos: bool) -> void:
	_set_submit_ui_busy(false)

	if result == Steam.RESULT_OK and not need_to_accept_tos:
		DraftStore.erase_draft(file_id)


func _show_blocking_error(message: String) -> void:
	AppLogger.error(message)
	var dlg := AcceptDialog.new()
	dlg.title = "Upload cancelled"
	dlg.dialog_text = message
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	var host := get_window()
	if host:
		host.add_child(dlg)
	else:
		add_child(dlg)
	dlg.popup_centered()
