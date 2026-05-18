extends CheckBox

func _on_toggled(toggled_on: bool) -> void:
	%TextEditDescription.editable = toggled_on
