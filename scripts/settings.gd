extends Control

@onready var exit_button = $ExitButton

func _ready():
	exit_button.grab_focus()
	
func _process(_delta):
	if Input.is_action_just_pressed("MenuBack"):
		exit_button.pressed.emit()
		
func _on_button_pressed() -> void:
	print("Exit pressed")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
