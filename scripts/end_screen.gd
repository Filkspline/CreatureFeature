extends Control

@onready var restart_label = $background/MarginContainer/VBoxContainer/HBoxContainer/restart_label
@onready var continue_label = $background/MarginContainer/VBoxContainer/HBoxContainer/continue_label
@onready var player_loss_label = $background/MarginContainer/VBoxContainer/HBoxContainer2/VBoxContainer/player_loss_label

var button_highlighted : int = 1 # 1 for restart, 2 for continue
var currently_selected_button_id : int = 1

# Edge-detection state for per-device input resolution (see _process below).
var _key_prev_state : Dictionary = {}
var _joy_button_prev_state : Dictionary = {}


func _ready() -> void:
	_handle_button_highlight(currently_selected_button_id)
	#EventBus.game_ended.connect(_on_player_loss)
	#print_rich("[color=yellow][END SCREEN] Connections to 'game_ended': %s" % EventBus.game_ended.get_connections())
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var device := _current_device()
	if device == null:
		return
	
	if _device_just_pressed(device, "Left"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		pass
	elif _device_just_pressed(device, "Right"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		pass

	if _device_just_pressed(device, "Normal"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_handle_button_pressed(currently_selected_button_id)


func _other_button(current_button_id : int) -> int:
	return 2 if current_button_id == 1 else 1

# NOTE: Does not currently work in emplementation, the connection occurs after the emit so nothing is
# recieved
func _on_player_loss(loser_id: int) -> void:
	print_rich("[color=yellow][END SCREEN] Loser id: %s" % loser_id)
	match loser_id:
		1:
			player_loss_label.text = "PLAYER_ONE_LOST"
		2:
			player_loss_label.text = "PLAYER_TWO_LOST"


func _handle_button_highlight(selected_button_id : int) -> void:
	match currently_selected_button_id:
		1:
			restart_label.text = "[RESTART]"
			continue_label.text = "CONTINUE"
		2:
			continue_label.text = "[CONTINUE]"
			restart_label.text = "RESTART"


func _handle_button_pressed(selected_button_id : int) -> void:
	match currently_selected_button_id:
		1:
			SceneTransition.change_scene("res://scenes/player_select.tscn")
		2:
			pass


# ── Per-device input resolution ──
# Mirrors player_select.gd: the selecting player is the PlayerInputDevice
# claimed for current_player_id during Player Select, so navigation and
# confirm route to the actual loser's device (WASD / arrows / a specific
# controller) rather than a hardcoded key set or an unfiltered joypad.


# TODO: I'll just have this temp locked to P1 Input this should be adjusted 
# to ideally take both player inputs
func _current_device() -> PlayerInputDevice:
	#if current_player_id == 1:
	return GameManager.p1_device
	#return GameManager.p2_device


func _device_just_pressed(device: PlayerInputDevice, action_name: String) -> bool:
	if device == null:
		return false
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return _keyboard_action_just_pressed(action_name, device.native_action_suffix)
	return _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name))


func _keyboard_action_just_pressed(base: String, suffix: String) -> bool:
	var just_pressed := false
	var keys: Array = GameManager.keyboard_layouts.get(suffix, {}).get(base, [])
	for event in keys:
		if not (event is InputEventKey):
			continue
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode
		var pressed: bool
		if code != KEY_NONE:
			pressed = Input.is_physical_key_pressed(code)
		else:
			code = key_event.keycode
			if code == KEY_NONE:
				continue
			pressed = Input.is_key_pressed(code)
		var was_pressed: bool = _key_prev_state.get(code, false)
		_key_prev_state[code] = pressed
		if pressed and not was_pressed:
			just_pressed = true
	return just_pressed


func _joy_button_for_action(action_name: String) -> int:
	match action_name:
		"Left":
			return JOY_BUTTON_DPAD_LEFT
		"Right":
			return JOY_BUTTON_DPAD_RIGHT
		_:
			return JOY_BUTTON_A


func _joy_button_just_pressed(device_id: int, button_index: int) -> bool:
	var key := "%d_%d" % [device_id, button_index]
	var pressed := Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed: bool = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed
