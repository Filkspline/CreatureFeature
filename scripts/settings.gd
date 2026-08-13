extends Node2D



func _on_button_pressed() -> void:
	print("Exit pressed")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
