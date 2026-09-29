extends Control

# ──────────────────────────────────────────────────────────────────
#  PlayerSelect (character / device select)
#
#  A cursor is the on-screen representation of ONE detected input mode:
#  either one of the two keyboard layouts that share the physical
#  keyboard (WASD -> "P1" actions, Arrows -> "P2" actions), or a single
#  connected controller. Every detected input mode gets its own cursor.
#
#  The two character panels are "slots":
#    slot 1 = Character 1 / Player 1 / Creature 1 (left)
#    slot 2 = Character 2 / Player 2 / Creature 2 (right)
#
#  A cursor moves left/right between the slots (through a neutral middle
#  position) and locks in on one. ONLY ONE CURSOR MAY OCCUPY A SLOT AT A
#  TIME: a cursor trying to enter a slot already occupied by another
#  cursor is blocked until that cursor leaves.
#
#  Locking a slot makes that input mode the corresponding player:
#    slot 1 -> Player 1 (character 1), slot 2 -> Player 2 (character 2).
#  Once both slots are locked, either player can confirm to start.

const FIGHT_SCENE := "res://scenes/pre_fight_upgrade_screen.tscn"
const LABBING_SCENE := "res://scenes/single_player.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

## Icon sheet the cursors draw from.
const CONTROL_SHEET := preload("res://assets/controls.tres")


const P1_ACCENT_COLOR := Color(1.0, 1.0, 1.0) # white
const P2_ACCENT_COLOR := Color(0.79607844, 0.85882354, 0.9882353) # cbdbfc

# Selection positions on the select screen.
const SLOT_1 := -1  # Character 1 / Player 1 / Creature 1
const NEUTRAL := 0
const SLOT_2 := 1   # Character 2 / Player 2 / Creature 2

@export var joy_normal_button : int = JOY_BUTTON_A # confirm / join
@export var joy_jump_button : int = JOY_BUTTON_X
@export var joy_special_button : int = JOY_BUTTON_B

const JOY_DIRECTION_BUTTONS := {
	"Left": JOY_BUTTON_DPAD_LEFT,
	"Right": JOY_BUTTON_DPAD_RIGHT,
	"Up": JOY_BUTTON_DPAD_UP,
	"Down": JOY_BUTTON_DPAD_DOWN,
}

# The two keyboard input modes share one physical keyboard. They are
# keyed by the InputMap suffix they drive ("P1"/"P2").
const KEYBOARD_LAYOUTS := {
	"P1": "Keyboard (WASD)",
	"P2": "Keyboard (Arrows)",
}
const KEYBOARD_ACTIONS := ["Left", "Right", "Up", "Down", "Normal", "Special", "Jump"]

# Buttons that count as "this controller is present" when joining.
const JOY_DETECT_BUTTONS := [
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
]
const JOY_DETECT_AXES := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]

const CURSOR_COLORS := [
	Color(1.0, 1.0, 1.0),                            # white
	Color(0.79607844, 0.85882354, 0.9882353),        # cbdbfc
	Color(1.0, 0.85, 0.4),                           # amber
	Color(0.55, 1.0, 0.6),                           # green
]

const CURSOR_SIZE := Vector2(51.0, 46.0)
const NEUTRAL_BASE_Y := 110.0
const NEUTRAL_STEP_Y := 79.0


# One detected input mode and its on-screen cursor.
class Cursor:
	var device: PlayerInputDevice
	var node: ColorRect
	var selection: int = 0
	var locked: bool = false
	var neutral_position: Vector2 = Vector2.ZERO
	var icon: AnimatedSprite2D

@onready var cursors_container: Node = $Cursors
@onready var character1: Control = $Characters/Character1
@onready var character2: Control = $Characters/Character2
@onready var character1_selected: Label = $Characters/Character1/SelectedLabel
@onready var character2_selected: Label = $Characters/Character2/SelectedLabel
@onready var p1_device_label: Label = $DeviceLabels/P1DeviceLabel
@onready var p2_device_label: Label = $DeviceLabels/P2DeviceLabel
@onready var start_button: Button = $Button
@onready var cursor_icons: Node = $CursorIcons
# The per-slot control legends, placed in the scene so their size, spacing and
# colours are tuned there rather than in code.
@onready var p1_legend: ControlPrompts = $Characters/Character1/ControlPrompts
@onready var p2_legend: ControlPrompts = $Characters/Character2/ControlPrompts

@onready var sprite_frames = preload("res://assets/controls.tres") 

var cursors: Array[Cursor] = []

var _created_keyboard: Dictionary = {}  # suffix -> true
var _created_joypad: Dictionary = {}    # device_id -> true

# Edge-detection state (see the helpers below).
var _key_prev_state: Dictionary = {}
var _joy_button_prev_state: Dictionary = {}
var _joy_axis_prev_state: Dictionary = {}
var _escape_was_pressed: bool = false

func _ready() -> void:
	GameManager.reset_player_select()
	start_button.visible = false
	_refresh_slot_labels()
	_refresh_legends()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(_delta: float) -> void:
	_detect_input_modes()
	for cursor in cursors:
		_handle_cursor(cursor)
	_refresh_slot_labels()

	if _escape_just_pressed():
		_back_out()


# Escape specifically, rather than the MenuBack action. MenuBack also carries
# a pad's B button, and B is the Special button players use to back out of a
# locked slot, so acting on the whole action would deselect and throw them out
# of the screen on the same press.
func _escape_just_pressed() -> bool:
	var pressed := Input.is_key_pressed(KEY_ESCAPE)
	var just_pressed := pressed and not _escape_was_pressed
	_escape_was_pressed = pressed
	return just_pressed


# Escape steps back out of the flow one level. This screen is reached from
# the main menu, so backing out goes there; the pre-fight upgrade screen uses
# the same step to come back here.
func _back_out() -> void:
	SfxManager.play_ui_select()
	SceneTransition.change_scene(MAIN_MENU_SCENE)

# ── Detecting input modes and creating cursors ──

func _detect_input_modes() -> void:
	for suffix in KEYBOARD_LAYOUTS:
		if _created_keyboard.get(suffix, false):
			continue
		if _keyboard_layout_just_pressed(suffix):
			_created_keyboard[suffix] = true
			_create_cursor(PlayerInputDevice.make_keyboard(KEYBOARD_LAYOUTS[suffix], suffix))

	for joy_id in Input.get_connected_joypads():
		if _created_joypad.get(joy_id, false):
			continue
		if _joypad_any_input(joy_id):
			_created_joypad[joy_id] = true
			_create_cursor(PlayerInputDevice.make_joypad(joy_id))


func _create_cursor(device: PlayerInputDevice) -> Cursor:
	var cursor := Cursor.new()
	
	_create_cursor_icon(device, cursor)
	
	cursor.device = device
	cursor.selection = NEUTRAL
	cursor.locked = false
	cursor.neutral_position = _neutral_position(cursors.size())

	var node := ColorRect.new()
	node.size = CURSOR_SIZE
	node.color = CURSOR_COLORS[cursors.size() % CURSOR_COLORS.size()]
	cursors_container.add_child(node)
	cursor.node = node

	cursors.append(cursor)
	_update_cursor_visual(cursor)
	
	cursor.node.hide()
	
	return cursor

func _create_cursor_icon(device: PlayerInputDevice, cursor: Cursor) -> void:
	var icon = AnimatedSprite2D.new()

	icon.sprite_frames = sprite_frames
	icon.z_index = 0
	# Matched on the device itself, not its display_name: a pad reports
	# whatever the OS calls it, so name matching never hit the controller
	# case and every pad fell back to the WASD icon.
	icon.frame = ControlScheme.movement_frame(ControlScheme.scheme_for(device))

	icon.modulate = CURSOR_COLORS[cursors.size() % CURSOR_COLORS.size()]
	cursor.icon = icon
	cursor_icons.add_child(icon)
	
	

# ── Per-cursor navigation / lock-in ──

func _handle_cursor(cursor: Cursor) -> void:
	if cursor.locked:
		# Backing out of a locked slot: Special releases it so that player can
		# pick again, whether or not both slots are filled yet.
		if _device_just_pressed(cursor.device, "Special"):
			_unlock_cursor(cursor)
			return
		# Once both players are locked, either one can confirm to start.
		if start_button.visible and _device_just_pressed(cursor.device, "Normal"):
			_on_button_pressed()
		return

	if _device_just_pressed(cursor.device, "Left"):
		_move_cursor(cursor, -1)
	elif _device_just_pressed(cursor.device, "Right"):
		_move_cursor(cursor, 1)

	if _device_just_pressed(cursor.device, "Normal"):
		_lock_cursor(cursor)


func _move_cursor(cursor: Cursor, delta: int) -> void:
	var new_selection := clampi(cursor.selection + delta, SLOT_1, SLOT_2)
	if new_selection == cursor.selection:
		return
	# Entering a character slot is only allowed while it's unoccupied.
	if new_selection != NEUTRAL and _slot_occupied_by_other(new_selection, cursor):
		return
	SfxManager.play_ui_hover()
	cursor.selection = new_selection
	_update_cursor_visual(cursor)
	# Moving onto a slot shows that slot's legend, so the controls are visible
	# while merely hovering, before anything is locked in.
	_refresh_legends()


func _slot_occupied_by_other(selection: int, cursor: Cursor) -> bool:
	for other in cursors:
		if other != cursor and other.selection == selection:
			return true
	return false


func _lock_cursor(cursor: Cursor) -> void:
	if cursor.selection == NEUTRAL:
		return
	SfxManager.play_ui_select()
	cursor.locked = true
	var slot := 1 if cursor.selection == SLOT_1 else 2
	_show_selected(slot)
	_store_character_choice(slot, cursor)
	print("P%d locked in by: %s" % [slot, cursor.device.display_name])
	_refresh_legend(slot)
	_check_both_locked()


# Backing out of a locked slot, so a player who confirmed by mistake can pick
# again instead of being stuck with it. Reached by pressing Special.
func _unlock_cursor(cursor: Cursor) -> void:
	if not cursor.locked:
		return
	SfxManager.play_ui_select()
	cursor.locked = false
	var slot := 1 if cursor.selection == SLOT_1 else 2
	var label := character1_selected if slot == 1 else character2_selected
	label.visible = false
	if slot == 1:
		GameManager.p1_character_id = 0
		GameManager.p1_device = null
	else:
		GameManager.p2_character_id = 0
		GameManager.p2_device = null
	_refresh_legend(slot)
	# Both slots are only "ready" while they are locked.
	start_button.visible = _locked_count() >= 2
	_refresh_slot_labels()


func _show_selected(slot: int) -> void:
	var label := character1_selected if slot == 1 else character2_selected
	label.visible = true
	label.modulate = P1_ACCENT_COLOR if slot == 1 else P2_ACCENT_COLOR


func _store_character_choice(slot: int, cursor: Cursor) -> void:
	if slot == 1:
		GameManager.p1_character_id = 1
		GameManager.p1_device = cursor.device
	else:
		GameManager.p2_character_id = 2
		GameManager.p2_device = cursor.device


# ── Control legend ──
# One ControlPrompts per slot, placed in the scene, showing what that player's
# device does. It appears as soon as a cursor is over the slot, hovering
# included, and stays while the slot is held, so the controls can be read
# before committing to a creature rather than only after.

func _refresh_legend(slot: int) -> void:
	var legend: ControlPrompts = p1_legend if slot == 1 else p2_legend
	if legend == null:
		return
	var cursor := _cursor_on_slot(slot)
	if cursor == null:
		legend.visible = false
		return
	legend.set_tint(P1_ACCENT_COLOR if slot == 1 else P2_ACCENT_COLOR)
	legend.set_device(cursor.device)
	legend.visible = true


func _refresh_legends() -> void:
	_refresh_legend(1)
	_refresh_legend(2)


# The cursor on a slot, whether it is just hovering there or has locked in.
func _cursor_on_slot(slot: int) -> Cursor:
	var selection := SLOT_1 if slot == 1 else SLOT_2
	for cursor in cursors:
		if cursor.selection == selection:
			return cursor
	return null


func _check_both_locked() -> void:
	if _locked_count() >= 2:
		start_button.visible = true


func _locked_count() -> int:
	var count := 0
	for cursor in cursors:
		if cursor.locked:
			count += 1
	return count


func _cursor_at(selection: int) -> Cursor:
	for cursor in cursors:
		if cursor.selection == selection:
			return cursor
	return null


# ── Visuals ──

func _update_cursor_visual(cursor: Cursor) -> void:
	match cursor.selection:
		SLOT_1:
			cursor.node.position = _character_position(character1, cursor.node)
		SLOT_2:
			cursor.node.position = _character_position(character2, cursor.node)
		_:
			cursor.node.position = cursor.neutral_position
	
	cursor.icon.position = cursor.node.position + (CURSOR_SIZE * 0.5)


func _character_position(character: Control, cursor: Control) -> Vector2:
	var character_center := character.position + character.size / 2.0
	return character_center - cursor.size / 2.0


func _neutral_position(index: int) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var x := viewport_size.x / 2.0 - CURSOR_SIZE.x / 2.0
	var y := NEUTRAL_BASE_Y + index * NEUTRAL_STEP_Y
	return Vector2(x, y)


func _refresh_slot_labels() -> void:
	p1_device_label.text = _slot_label(_cursor_at(SLOT_1))
	p2_device_label.text = _slot_label(_cursor_at(SLOT_2))


func _slot_label(cursor: Cursor) -> String:
	if cursor == null:
		return "PRESS A BUTTON TO JOIN"
	return "DEVICE: %s" % cursor.device.display_name


# ── Disconnects ──

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		return
	_created_joypad.erase(device_id)
	for cursor in cursors:
		if cursor.device.kind == PlayerInputDevice.Kind.JOYPAD and cursor.device.device_id == device_id:
			_remove_cursor(cursor)
			break
	_refresh_slot_labels()


func _remove_cursor(cursor: Cursor) -> void:
	if cursor.locked:
		var slot := 1 if cursor.selection == SLOT_1 else 2
		var label := character1_selected if slot == 1 else character2_selected
		label.visible = false
		if slot == 1:
			GameManager.p1_character_id = 0
			GameManager.p1_device = null
		else:
			GameManager.p2_character_id = 0
			GameManager.p2_device = null
		# A pad pulling out takes its legend with it.
		_refresh_legend(slot)
		start_button.visible = _locked_count() >= 2

	cursors.erase(cursor)
	if is_instance_valid(cursor.node):
		cursor.node.queue_free()
	start_button.visible = _locked_count() >= 2



func _device_just_pressed(device: PlayerInputDevice, action_name: String) -> bool:
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return _keyboard_action_just_pressed(action_name, device.native_action_suffix)
	# A controller can answer with either the d-pad/button for this base or
	# the left stick pushed that way. Both are checked: reading buttons only
	# meant the stick could not move a cursor or confirm on this screen,
	# even though the same stick works in a fight.
	if _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name)):
		return true
	return _joy_axis_just_pressed(device.device_id, action_name)


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
	if action_name == "Jump":
		return joy_jump_button
	return joy_normal_button


func _joy_button_just_pressed(device_id: int, button_index: int) -> bool:
	var key := "%d_%d" % [device_id, button_index]
	var pressed := Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed: bool = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed


# Stick equivalent of a d-pad press for the directional bases, edge detected
# the same way the button checks are. Shares GameManager's axis map and
# threshold so a stick tilt means the same thing here as it does in a fight.
func _joy_axis_just_pressed(device_id: int, action_name: String) -> bool:
	var binding: Array = GameManager.JOY_AXIS_BASES.get(action_name, [])
	if binding.is_empty():
		return false
	var axis: int = binding[0]
	var direction: float = binding[1]
	var pressed := Input.get_joy_axis(device_id, axis) * direction >= GameManager.JOY_AXIS_DEADZONE
	var key := "%d_%d_%s" % [device_id, axis, direction]
	var was_pressed: bool = _joy_axis_prev_state.get(key, false)
	_joy_axis_prev_state[key] = pressed
	return pressed and not was_pressed


func _joypad_any_input(device_id: int) -> bool:
	var any := false
	for button in JOY_DETECT_BUTTONS:
		if _joy_button_just_pressed(device_id, button):
			any = true
	for axis in JOY_DETECT_AXES:
		if absf(Input.get_joy_axis(device_id, axis)) > 0.5:
			any = true
	return any


func _on_button_pressed() -> void:
	SfxManager.play_ui_select()
	var slot1 := _cursor_at(SLOT_1)
	var slot2 := _cursor_at(SLOT_2)
	if slot1:
		GameManager.p1_device = slot1.device
	if slot2:
		GameManager.p2_device = slot2.device
	GameManager.bind_player_inputs()
	match GameManager.mode_id:
		1:
			SceneTransition.change_scene(FIGHT_SCENE)
		2:
			SceneTransition.change_scene(LABBING_SCENE)
