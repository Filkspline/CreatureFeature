extends Node2D

@onready var play_button = $Buttons/Play
@onready var settings_button = $Buttons/Settings
@onready var quit_button = $Buttons/Quit

var buttons: Array[Button]
var selected_index := 0


func _ready():
	buttons = [play_button, settings_button, quit_button]
	
	# Automatically select Play when the menu opens
	buttons[selected_index].grab_focus()


func _process(_delta):
	# Move selection down
	if Input.is_action_just_pressed("MenuDown"):
		selected_index += 1
		if selected_index >= buttons.size():
			selected_index = 0
		
		buttons[selected_index].grab_focus()

	# Move selection up
	if Input.is_action_just_pressed("MenuUp"):
		selected_index -= 1
		if selected_index < 0:
			selected_index = buttons.size() - 1
		
		buttons[selected_index].grab_focus()

	# Select current button
	if Input.is_action_just_pressed("MenuSelect"):
		buttons[selected_index].pressed.emit()


func _on_play_pressed():
	print("Play pressed")
	get_tree().change_scene_to_file("res://scenes/player_select.tscn")


func _on_settings_pressed():
	get_tree().change_scene_to_file("res://scenes/settings.tscn")


func _on_quit_pressed():
	print("Quit pressed")
	get_tree().quit()
