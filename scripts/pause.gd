extends Control

@onready var resume_button = $PanelContainer/VBoxContainer/Resume
@onready var quit_button = $PanelContainer/VBoxContainer/Quit

var buttons: Array[Button]
var selected_index := 0


func _ready():
	buttons = [resume_button, quit_button]
	
	hide()
	$AnimationPlayer.play("RESET")


func resume():
	get_tree().paused = false
	$AnimationPlayer.play_backwards("blur")
	hide()


func pause():
	show()
	get_tree().paused = true
	
	# Start with Resume selected
	selected_index = 0
	buttons[selected_index].grab_focus()
	
	$AnimationPlayer.play("blur")


func testEsc():
	if Input.is_action_just_pressed("pause"):
		if get_tree().paused:
			resume()
		else:
			pause()


func _process(_delta):
	testEsc()
	
	# Controller / keyboard menu movement
	if not get_tree().paused:
		return
	
	if Input.is_action_just_pressed("MenuDown"):
		selected_index += 1
		
		if selected_index >= buttons.size():
			selected_index = 0
		
		buttons[selected_index].grab_focus()


	if Input.is_action_just_pressed("MenuUp"):
		selected_index -= 1
		
		if selected_index < 0:
			selected_index = buttons.size() - 1
		
		buttons[selected_index].grab_focus()


	if Input.is_action_just_pressed("MenuSelect"):
		buttons[selected_index].pressed.emit()


func _on_resume_pressed() -> void:
	resume()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	SceneTransition.change_scene("res://scenes/main_menu.tscn")
