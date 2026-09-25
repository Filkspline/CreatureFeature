extends Node2D

@onready var multiplayer_button = $Buttons/VBoxContainer/Multiplayer
@onready var singleplayer_button = $Buttons/VBoxContainer/Singleplayer
@onready var settings_button = $Buttons/VBoxContainer/Settings
@onready var quit_button = $Buttons/VBoxContainer/Quit

var buttons: Array[Button]
var selected_index := 0


func _ready():
	buttons = [multiplayer_button, singleplayer_button, settings_button, quit_button]
	
	# Automatically select Play when the menu opens
	buttons[selected_index].grab_focus()


func _process(_delta):
	# Move selection down
	if Input.is_action_just_pressed("MenuDown"):
		selected_index += 1
		if selected_index >= buttons.size():
			selected_index = 0
		
		buttons[selected_index].grab_focus()
		SfxManager.play_ui_hover()

	# Move selection up
	if Input.is_action_just_pressed("MenuUp"):
		selected_index -= 1
		if selected_index < 0:
			selected_index = buttons.size() - 1
		
		buttons[selected_index].grab_focus()
		SfxManager.play_ui_hover()

	# Select current button
	if Input.is_action_just_pressed("MenuSelect"):
		buttons[selected_index].pressed.emit()


func _on_multiplayer_pressed():
	print("Multiplayer pressed")
	SfxManager.play_ui_select()
	GameManager.mode_id = 1
	SceneTransition.change_scene("res://scenes/player_select.tscn")

func _on_singleplayer_pressed() -> void:
	print("Singleplayer pressed")
	SfxManager.play_ui_select()
	GameManager.mode_id = 2
	SceneTransition.change_scene("res://scenes/player_select.tscn")

func _on_settings_pressed():
	SfxManager.play_ui_select()
	SceneTransition.change_scene("res://scenes/settings.tscn")


func _on_quit_pressed():
	print("Quit pressed")
	SfxManager.play_ui_select()
	get_tree().quit()
