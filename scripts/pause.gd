extends Control

@onready var resume_button = $HBoxContainer/PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/Resume
@onready var quit_button = $HBoxContainer/PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/Quit
@onready var p1_controls : Control = $HBoxContainer/p1_controls
@onready var p2_controls : Control = $HBoxContainer/p2_controls
# Grows the focused entry's text, same node and tuning as the main menu.
@onready var focus_emphasis : MenuFocusEmphasis = get_node_or_null("MenuFocusEmphasis")

var buttons: Array[Button]
var selected_index := 0


func _ready():
	buttons = [resume_button, quit_button]

	if focus_emphasis:
		focus_emphasis.register_buttons(buttons)

	# Guarded: this node is instantiated with the level, and a device is only
	# claimed once someone has picked one, so dereferencing either device here
	# crashed whenever the level was opened without going through player
	# select (or after reset_player_select()).
	print_rich("[color=yellow][INPUT] P1 Input: %s | P2 Input: %s" % [
		_device_name(GameManager.p1_device),
		_device_name(GameManager.p2_device),
	])

	hide()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	$AnimationPlayer.play("RESET")


func _device_name(device: PlayerInputDevice) -> String:
	return device.display_name if device else "none"


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
	_show_legend_for_pauser()
	
	$AnimationPlayer.play("blur")


# Shows the controls panel belonging to whoever actually paused, so a
# controller player sees controller buttons rather than a generic default.
func _show_legend_for_pauser() -> void:
	var pauser := _pausing_player()
	p1_controls.visible = pauser != 2
	p2_controls.visible = pauser != 1


# 1 or 2 for the player whose own device sent the pause, 0 when it can't be
# attributed. A pad's START button identifies its owner exactly; the keyboard
# shares one Escape key between both layouts, so that case shows both panels
# rather than guessing and showing one player the wrong controls.
func _pausing_player() -> int:
	for slot in [1, 2]:
		var device: PlayerInputDevice = GameManager.p1_device if slot == 1 else GameManager.p2_device
		if device and device.kind == PlayerInputDevice.Kind.JOYPAD:
			if Input.is_joy_button_pressed(device.device_id, JOY_BUTTON_START):
				return slot
	return 0


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
		SfxManager.play_ui_hover()


	if Input.is_action_just_pressed("MenuUp"):
		selected_index -= 1
		
		if selected_index < 0:
			selected_index = buttons.size() - 1
		
		buttons[selected_index].grab_focus()
		SfxManager.play_ui_hover()


	if Input.is_action_just_pressed("MenuSelect"):
		buttons[selected_index].pressed.emit()


func _on_resume_pressed() -> void:
	SfxManager.play_ui_select()
	resume()

func _on_quit_pressed() -> void:
	SfxManager.play_ui_select()
	get_tree().paused = false
	# Same reset as end_screen.gd's restart: quitting to the main menu mid
	# match has to clear round counts and picked upgrades, otherwise a new
	# match inherits the state from the one that was just abandoned.
	GameManager.reset_player_select()
	GameManager.start_match()
	SceneTransition.change_scene("res://scenes/main_menu.tscn")
