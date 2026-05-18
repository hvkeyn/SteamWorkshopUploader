extends Button

func _ready() -> void:
	disabled = true
	pressed.connect(_on_pressed)
	if has_node("%ItemListFiles"):
		%ItemListFiles.item_selected.connect(_on_tree_selection_changed)
	if has_node("%ButtonBrowseFiles"):
		%ButtonBrowseFiles.target_path_changed.connect(_on_target_path_changed)


func _on_target_path_changed(path: String) -> void:
	disabled = path.is_empty() or not _has_tree_selection()


func _on_tree_selection_changed() -> void:
	disabled = not _has_tree_selection()


func _has_tree_selection() -> bool:
	if not has_node("%ItemListFiles"):
		return false
	return %ItemListFiles.get_selected_relative_path() != ""


func _on_pressed() -> void:
	if has_node("%ItemListFiles"):
		%ItemListFiles.remove_selected_from_list()
