extends Control

# ──────────────────────────────────────────────────────────────────
#  SinglePlayerSelect
#
#  Practice Range's own select screen: one creature slot instead of two,
#  because the lab is a single player against the training dummy and there is
#  nothing for a second player to claim.
#
#  Everything else works like player_select.gd: any input mode that presses a
#  button joins and claims the slot with its device, Normal confirms, Special
#  backs out of a confirmed slot, and Start (once the slot is confirmed) binds
#  that device and moves on to the lab.
#
#  Input is resolved per device through PlayerInputDevice and GameManager's
#  captured keyboard layouts, the way every other menu does it, rather than
#  reading raw action names.

const LAB_SCENE := "res://scenes/single_player.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

const CONTROL_SHEET := preload("res://assets/controls.tres")

const ACCENT_COLOR := Color(1.0, 1.0, 1.0)

const CURSOR_SIZE := Vector2(51.0, 46.0)
const CURSOR_NEUTRAL_OFFSET := Vector2(0.0, 150.0)

const JOY_DIRECTION_BUTTONS := {
	"Left": JOY_BUTTON_DPAD_LEFT,
	"Right": JOY_BUTTON_DPAD_RIGHT,
	"Up": JOY_BUTTON_DPAD_UP,
	"Down": JOY_BUTTON_DPAD_DOWN,
}
const KEYBOARD_LAYOUTS := {
	"P1": "Keyboard (WASD)",
	"P2": "Keyboard (Arrows)",
}
const KEYBOARD_ACTIONS := ["Left", "Right", "Up", "Down", "Normal", "Special", "Jump"]
const JOY_DETECT_BUTTONS := [
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
]
const JOY_DETECT_AXES := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]

@export var joy_normal_button : int = JOY_BUTTON_A
@export var joy_special_button : int = JOY_BUTTON_B

## One joined input mode and its on-screen cursor.
class Cursor:
	var device: PlayerInputDevice
	var node: ColorRect
	var icon: AnimatedSprite2D
	var locked: bool = false

@onready var cursors_container : Node = $Cursors
@onready var cursor_icons : Node = $CursorIcons
@onready var character_slot : Panel = $Characters/Character1
@onready var ready_label : Label = $Characters/Character1/SelectedLabel
@onready var legend : ControlPrompts = $Characters/Character1/ControlPrompts
@onready var device_label : Label = $DeviceLabel
@onready var start_button : Button = $StartButton

var cursor : Cursor = null

var _created_keyboard : Dictionary = {}
var _created_joypad : Dictionary = {}
var _key_prev_state : Dictionary = {}
var _joy_button_prev_state : Dictionary = {}
var _joy_axis_prev_state : Dictionary = {}
var _escape_was_pressed : bool = false


func _ready() -> void:
	GameManager.reset_player_select()
	start_button.visible = false
	ready_label.visible = false
	legend.visible = false
	device_label.text = "PRESS A BUTTON TO JOIN"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The slot is clickable too, so the mouse can join and confirm as well as
	# the device buttons can.
	character_slot.gui_input.connect(_on_slot_gui_input)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(_delta: float) -> void:
	_detect_input_modes()
	_refresh_device_label()
	if cursor != null:
		_handle_cursor(cursor)
	if _escape_just_pressed():
		_back_out()


func _detect_input_modes() -> void:
	if cursor != null:
		return
	for suffix in KEYBOARD_LAYOUTS:
		if _created_keyboard.get(suffix, false):
			continue
		if _keyboard_layout_just_pressed(suffix):
			_created_keyboard[suffix] = true
			_join(PlayerInputDevice.make_keyboard(KEYBOARD_LAYOUTS[suffix], suffix))
			return
	for joy_id in Input.get_connected_joypads():
		if _created_joypad.get(joy_id, false):
			continue
		if _joypad_any_input(joy_id):
			_created_joypad[joy_id] = true
			_join(PlayerInputDevice.make_joypad(joy_id))
			return


# Gives the joining input mode its cursor and leaves it sitting on the slot:
# with only one slot there is nothing to move between, so a cursor appears
# already hovering the creature.
func _join(device: PlayerInputDevice) -> void:
	var new_cursor := Cursor.new()
	new_cursor.device = device

	var node := ColorRect.new()
	node.size = CURSOR_SIZE
	node.color = ACCENT_COLOR
	node.position = _slot_cursor_position(node)
	cursors_container.add_child(node)
	new_cursor.node = node

	_create_cursor_icon(device, new_cursor)

	cursor = new_cursor
	_refresh_legend()
	_refresh_device_label()
	SfxManager.play_ui_hover()


func _create_cursor_icon(device: PlayerInputDevice, target : Cursor) -> void:
	var icon := AnimatedSprite2D.new()
	icon.sprite_frames = CONTROL_SHEET
	icon.z_index = 0
	icon.frame = ControlScheme.movement_frame(ControlScheme.scheme_for(device))
	icon.position = target.node.position + CURSOR_SIZE * 0.5
	cursor_icons.add_child(icon)
	target.icon = icon


func _slot_cursor_position(node : Control) -> Vector2:
	var centre := character_slot.position + character_slot.size * 0.5
	return centre - node.size * 0.5


func _handle_cursor(target : Cursor) -> void:
	if _device_just_pressed(target.device, "Special"):
		_unlock()
		return
	if _confirm_pressed(target.device):
		_confirm()


# Confirming: start once the slot is held, otherwise hold it.
func _confirm() -> void:
	if cursor == null:
		return
	if cursor.locked:
		_start_lab()
	else:
		_lock()


# Enter confirms on top of this player's own Normal button, so a keyboard
# player can always select with Enter. Only consulted for a keyboard device:
# ui_accept also answers to a pad's A, which would double up with the device
# check above.
func _confirm_pressed(device: PlayerInputDevice) -> bool:
	if _device_just_pressed(device, "Normal"):
		return true
	if device == null or device.kind != PlayerInputDevice.Kind.KEYBOARD:
		return false
	return Input.is_action_just_pressed("ui_accept")


# Left click on the creature slot does the same thing Enter does.
func _on_slot_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if cursor == null:
		return
	_confirm()


func _lock() -> void:
	if cursor == null or cursor.locked:
		return
	cursor.locked = true
	SfxManager.play_ui_select()
	ready_label.show()
	var pop := create_tween()
	pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ready_label.scale = Vector2.ONE * 1.6
	pop.tween_property(ready_label, "scale", Vector2.ONE, 0.25)
	_update_loading_bar()
	start_button.visible = true
	start_button.grab_focus()


func _unlock() -> void:
	if cursor == null or not cursor.locked:
		return
	cursor.locked = false
	SfxManager.play_ui_select()
	ready_label.hide()
	start_button.visible = false
	_update_loading_bar()


func _update_loading_bar() -> void:
	# The slot's border colour is the whole loading bar here: filled while the
	# player is holding a confirmed slot.
	var style := character_slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	# Blue, not green: the palette is white, blue and black.
	style.border_color = ACCENT_COLOR.lerp(Color(0.79607844, 0.85882354, 0.9882353), 1.0 if (cursor != null and cursor.locked) else 0.0)


func _start_lab() -> void:
	if cursor == null or not cursor.locked:
		return
	SfxManager.play_ui_select()
	GameManager.p1_character_id = 1
	GameManager.p1_device = cursor.device
	GameManager.p2_device = null
	GameManager.bind_player_inputs()
	GameManager.mode_id = 2
	SceneTransition.change_scene(LAB_SCENE)


func _back_out() -> void:
	SfxManager.play_ui_select()
	SceneTransition.change_scene(MAIN_MENU_SCENE)


func _refresh_device_label() -> void:
	if cursor == null:
		device_label.text = "PRESS A BUTTON TO JOIN"
		return
	device_label.text = "DEVICE: %s" % cursor.device.display_name


func _refresh_legend() -> void:
	if legend == null:
		return
	if cursor == null:
		legend.visible = false
		return
	legend.set_player(1)
	legend.set_device(cursor.device)
	legend.set_tint(ACCENT_COLOR)
	legend.visible = true


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		return
	_created_joypad.erase(device_id)
	if cursor != null and cursor.device.kind == PlayerInputDevice.Kind.JOYPAD and cursor.device.device_id == device_id:
		if is_instance_valid(cursor.node):
			cursor.node.queue_free()
		if is_instance_valid(cursor.icon):
			cursor.icon.queue_free()
		cursor = null
		ready_label.hide()
		start_button.visible = false
		_refresh_legend()


func _escape_just_pressed() -> bool:
	var pressed := Input.is_key_pressed(KEY_ESCAPE)
	var just_pressed := pressed and not _escape_was_pressed
	_escape_was_pressed = pressed
	return just_pressed


# ── Per-device input resolution ──
# Same helpers the other menus use: a device answers either through its own
# keys (keyboard) or its d-pad/buttons and stick (controller).

func _device_just_pressed(device: PlayerInputDevice, action_name: String) -> bool:
	if device == null:
		return false
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return _keyboard_action_just_pressed(action_name, device.native_action_suffix)
	if _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name)):
		return true
	return _joy_axis_just_pressed(device.device_id, action_name)


func _keyboard_action_just_pressed(base: String, suffix: String) -> bool:
	var just_pressed := false
	var keys : Array = GameManager.keyboard_layouts.get(suffix, {}).get(base, [])
	for event in keys:
		if not (event is InputEventKey):
			continue
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode
		var pressed : bool
		if code != KEY_NONE:
			pressed = Input.is_physical_key_pressed(code)
		else:
			code = key_event.keycode
			if code == KEY_NONE:
				continue
			pressed = Input.is_key_pressed(code)
		var was_pressed : bool = _key_prev_state.get(code, false)
		_key_prev_state[code] = pressed
		if pressed and not was_pressed:
			just_pressed = true
	return just_pressed


func _keyboard_layout_just_pressed(suffix: String) -> bool:
	var any := false
	for action in KEYBOARD_ACTIONS:
		if _keyboard_action_just_pressed(action, suffix):
			any = true
	return any


func _joy_button_for_action(action_name: String) -> int:
	if JOY_DIRECTION_BUTTONS.has(action_name):
		return JOY_DIRECTION_BUTTONS[action_name]
	if action_name == "Special":
		return joy_special_button
	return joy_normal_button


func _joy_button_just_pressed(device_id: int, button_index: int) -> bool:
	var key := "%d_%d" % [device_id, button_index]
	var pressed := Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed : bool = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed


func _joy_axis_just_pressed(device_id: int, action_name: String) -> bool:
	var binding : Array = GameManager.JOY_AXIS_BASES.get(action_name, [])
	if binding.is_empty():
		return false
	var axis : int = binding[0]
	var direction : float = binding[1]
	var pressed := Input.get_joy_axis(device_id, axis) * direction >= GameManager.JOY_AXIS_DEADZONE
	var key := "%d_%d_%s" % [device_id, axis, direction]
	var was_pressed : bool = _joy_axis_prev_state.get(key, false)
	_joy_axis_prev_state[key] = pressed
	return pressed and not was_pressed


func _joypad_any_input(device_id: int) -> bool:
	for button in JOY_DETECT_BUTTONS:
		if _joy_button_just_pressed(device_id, button):
			return true
	for axis in JOY_DETECT_AXES:
		if absf(Input.get_joy_axis(device_id, axis)) > 0.5:
			return true
	return false
