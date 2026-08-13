extends Control

@onready var exit_button = $ExitButton


func _ready():
	exit_button.grab_focus()


func _process(_delta):
	# Custom select button
	if Input.is_action_just_pressed("MenuSelect"):
		var focused = get_viewport().gui_get_focus_owner()
		
		if focused != null:
			print("Focused: ", focused)
			
			# Normal buttons
			if focused is Button:
				focused.pressed.emit()


	# B / Circle
	if Input.is_action_just_pressed("MenuBack"):
		_on_exit_button_pressed()


func _on_exit_button_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
