extends Button

func _on_pressed() -> void:
	var edit_screen := get_tree().get_first_node_in_group("ugc_edit_screen")
	if edit_screen and edit_screen.has_method("save_draft_now"):
		edit_screen.save_draft_now()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
