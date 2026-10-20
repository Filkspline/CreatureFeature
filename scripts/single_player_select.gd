extends Control

# ──────────────────────────────────────────────────────────────────
#  SinglePlayerSelect - the input select screen for Practice Range.
#
#  Practice Range has one player and a training dummy, so it gets its own
#  screen instead of borrowing local multiplayer's. Sharing that screen meant
#  the single-player layout had to slide the surviving creature's box into the
#  middle of the screen - which is exactly where the waiting cursors are laid
#  out - so a device that had just pressed a button appeared to already be
#  sitting in the creature's slot: the input and the thing the input was
#  choosing were drawn on top of each other.
#
#  This screen keeps them apart. There are two places a cursor can be, and they
#  are deliberately in different parts of the screen:
#
#    * the SLOT  - the creature's box in the upper middle, and
#    * a BAY     - that device's own outlined place in the tray along the
#                  bottom, one per detected input mode.
#
#  So "where my input is" and "what my input has claimed" are never the same
#  place, no matter how many devices are plugged in.
#
#  Everything else works the way the multiplayer screen taught players, because
#  it is the same set of features: every input mode that presses something gets
#  its own cursor (both keyboard layouts sharing the keyboard, and every
#  connected pad), a cursor takes the creature with Up or Select, Select locks
#  it in (SELECTED! pops in), Special or Down gives it back, Start appears once
#  it is held, and a pad that is pulled out drops its claim. Only one cursor can
#  hold the creature at a time.
#
#  Enter counts as Select for a keyboard device, so the whole screen can be
#  driven with Enter and Escape alone.
#
#  Not carried over from the multiplayer screen, because Practice Range has no
#  second player: the second creature's box, the online cursor sync and the RPC
#  hooks an online match needs. Nothing here is claimed until a device confirms.
# ──────────────────────────────────────────────────────────────────

const LAB_SCENE := "res://scenes/single_player.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

## Icon sheet the cursors draw from.
const CONTROL_SHEET := preload("res://assets/controls.tres")

# White and the light blue accent only: this project's palette is white, blue
# and black.
const P1_ACCENT_COLOR := Color(1.0, 1.0, 1.0)

# Where a cursor is. Two places, in two parts of the screen (see the header).
const PLACE_TRAY := 0
const PLACE_SLOT := 1

@export var joy_normal_button : int = JOY_BUTTON_A # confirm / join
@export var joy_jump_button : int = JOY_BUTTON_X
@export var joy_special_button : int = JOY_BUTTON_B

@export_group("Layout")
## The cursor square a device is drawn as. Sized to match a tray bay, so a
## device looks the same waiting in its bay as it does sitting in the slot.
@export var cursor_size : Vector2 = Vector2(51.0, 46.0)
## How long a cursor takes to travel between its bay and the creature. Same beat
## as the versus select screen and the menu focus emphasis.
const CURSOR_SLIDE_SECONDS := 0.16
## The sheet's frames are 100x100, so this is roughly pixels of icon per 100
## pixels of sheet.
@export var cursor_icon_scale : float = 0.46
## Distance from one bay's left edge to the next. Read from the scene so
## widening the bays cannot silently make them overlap.
@export var tray_bay_spacing : float = 76.0

@export_group("State colours")
## The creature slot's border while it is open, and while a device holds it.
## The claimed colour is the blue accent, so holding the creature reads as the
## same kind of signal the rest of the project uses.
@export var open_border_color : Color = Color(1.0, 1.0, 1.0)
@export var claimed_border_color : Color = Color(0.79607844, 0.85882354, 0.9882353)

@export_group("Lock-in feedback")
## How far the cursor punches up the moment the creature is confirmed, and how
## long it takes to settle back. Same springy TRANS_BACK pop the cards use.
@export var lock_punch_scale : float = 1.4
@export var lock_punch_duration : float = 0.3
## The SELECTED label pops in from this scale instead of just appearing.
@export var selected_label_pop_scale : float = 1.8
@export var selected_label_pop_duration : float = 0.35

const JOY_DIRECTION_BUTTONS := {
	"Left": JOY_BUTTON_DPAD_LEFT,
	"Right": JOY_BUTTON_DPAD_RIGHT,
	"Up": JOY_BUTTON_DPAD_UP,
	"Down": JOY_BUTTON_DPAD_DOWN,
}

# The two keyboard input modes share one physical keyboard. They are keyed by
# the InputMap suffix they drive ("P1"/"P2"), which is also the layout whose
# keys each cursor answers to.
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

## Alternating so two devices waiting side by side are told apart at a glance.
## White and the blue accent only.
const CURSOR_COLORS := [
	Color(1.0, 1.0, 1.0), # white
	Color(0.79607844, 0.85882354, 0.9882353), # cbdbfc
]


# One detected input mode and the cursor that represents it.
class Cursor:
	var device: PlayerInputDevice
	var node: ColorRect
	var icon: AnimatedSprite2D
	## 0 = waiting in its own bay, 1 = sitting in the creature's slot.
	## Literal so this inner class does not depend on the outer constants.
	var place: int = 0
	var locked: bool = false
	## Which bay in the tray belongs to this device. Kept in join order.
	var bay_index: int = 0
	## The tween currently sliding this cursor, so a new move can take over from
	## one still in flight instead of fighting it.
	var slide: Tween = null

@onready var cursors_container : Node = $Cursors
@onready var cursor_icons : Node = $CursorIcons
@onready var character_slot : Panel = $Characters/Character1
@onready var ready_label : Label = $Characters/Character1/SelectedLabel
@onready var device_label : Label = $DeviceLabel
@onready var start_button : Button = $StartButton
@onready var tray_area : Control = $TrayArea
@onready var tray_bays : Node = $TrayBays
@onready var tray_bay_template : Control = $TrayBayTemplate
@onready var legends : Control = $Legends
# One ControlPrompts for what this device does on THIS screen and one for what
# it does in the lab, both placed in the scene so their size, spacing and
# colours are tuned there rather than in code.
@onready var screen_prompts : ControlPrompts = $Legends/ScreenPrompts
@onready var lab_prompts : ControlPrompts = $Legends/LabPrompts

var cursors: Array[Cursor] = []

var _created_keyboard : Dictionary = {} # suffix -> true
var _created_joypad : Dictionary = {} # device_id -> true

# Edge-detection state (see the helpers below).
var _key_prev_state : Dictionary = {}
var _joy_button_prev_state : Dictionary = {}
var _joy_axis_prev_state : Dictionary = {}
var _escape_was_pressed : bool = false
var _starting_match : bool = false

# The device whose controls the two legends are showing, and whether they are
# showing at all, so the prompts are only rebuilt when that actually changes.
var _legend_device : PlayerInputDevice = null
var _legends_visible : bool = false


func _ready() -> void:
	GameManager.reset_player_select()
	start_button.visible = false
	ready_label.visible = false
	legends.visible = false
	_rebuild_bays()
	_update_slot_border()
	_refresh_device_label()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(_delta: float) -> void:
	_detect_input_modes()
	for cursor in cursors:
		_handle_cursor(cursor)
		# Positions are derived from the slot's and the tray's own rects every
		# frame, so moving either in the scene moves its cursors with it.
		_update_cursor_visual(cursor)
	_refresh_device_label()

	if _escape_just_pressed():
		_back_out()


# Escape specifically, rather than the MenuBack action. MenuBack also carries a
# pad's B button, and B is the Special button a player uses to give the creature
# back, so acting on the whole action would drop their claim and throw them out
# of the screen on the same press.
func _escape_just_pressed() -> bool:
	var pressed := Input.is_key_pressed(KEY_ESCAPE)
	var just_pressed := pressed and not _escape_was_pressed
	_escape_was_pressed = pressed
	return just_pressed


# Escape steps back out of the flow one level. This screen is reached from the
# main menu, so backing out goes there.
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
			_add_cursor(PlayerInputDevice.make_keyboard(KEYBOARD_LAYOUTS[suffix], suffix))

	for joy_id in Input.get_connected_joypads():
		if _created_joypad.get(joy_id, false):
			continue
		if _joypad_any_input(joy_id):
			_created_joypad[joy_id] = true
			_add_cursor(PlayerInputDevice.make_joypad(joy_id))


# One cursor per detected input mode, waiting in the next free bay. Nothing is
# claimed by joining: the device still has to take the slot.
func _add_cursor(device: PlayerInputDevice) -> Cursor:
	var cursor := Cursor.new()
	cursor.device = device
	cursor.place = PLACE_TRAY
	cursor.locked = false
	cursor.bay_index = cursors.size()

	var node := ColorRect.new()
	node.size = cursor_size
	node.color = CURSOR_COLORS[cursors.size() % CURSOR_COLORS.size()]
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursors_container.add_child(node)
	cursor.node = node

	_create_cursor_icon(device, cursor)

	cursors.append(cursor)
	_rebuild_bays()
	_place_cursor_offscreen(cursor)
	_update_cursor_visual(cursor)
	_refresh_legends()
	_refresh_ready_state()
	SfxManager.play_ui_hover()

	return cursor


# New cursors start above the top edge of the screen, horizontally centred, so
# they slide in from the top middle rather than from the origin.
func _place_cursor_offscreen(cursor: Cursor) -> void:
	var spawn := Vector2(
		get_viewport_rect().size.x * 0.5 - cursor_size.x * 0.5,
		-cursor_size.y * 1.5
	)
	if is_instance_valid(cursor.node):
		cursor.node.position = spawn
	if is_instance_valid(cursor.icon):
		cursor.icon.position = spawn + (cursor_size * 0.5)


func _create_cursor_icon(device: PlayerInputDevice, cursor: Cursor) -> void:
	var icon := AnimatedSprite2D.new()
	icon.sprite_frames = CONTROL_SHEET
	icon.z_index = 0
	# Matched on the device itself, not its display_name: a pad reports whatever
	# the OS calls it, so name matching never hit the controller case and every
	# pad fell back to the WASD icon.
	icon.frame = ControlScheme.movement_frame(ControlScheme.scheme_for(device))
	icon.scale = Vector2.ONE * cursor_icon_scale
	icon.modulate = cursor.node.color
	cursor.icon = icon
	cursor_icons.add_child(icon)


# ── Per-cursor navigation / lock-in ──

func _handle_cursor(cursor: Cursor) -> void:
	if cursor.locked:
		# Giving the creature back so another device can take it, or so this
		# device can pick again.
		if _device_just_pressed(cursor.device, "Special"):
			_unlock_cursor(cursor)
			return
		# Once the creature is held, Select starts the lab.
		if start_button.visible and _confirm_just_pressed(cursor.device):
			_on_button_pressed()
		return

	if cursor.place == PLACE_TRAY:
		# Up moves the cursor onto the creature without committing to it, so its
		# controls can be read first; Select does the same and holds it, so a
		# player who just presses the button they are told to press is not left
		# wondering where their cursor went.
		if _device_just_pressed(cursor.device, "Up"):
			_take_slot(cursor, false)
		elif _confirm_just_pressed(cursor.device):
			_take_slot(cursor, true)
		return

	# Sitting in the creature's slot, not holding it yet.
	if _device_just_pressed(cursor.device, "Down") or _device_just_pressed(cursor.device, "Special"):
		_return_to_tray(cursor)
		return
	if _confirm_just_pressed(cursor.device):
		_lock_cursor(cursor)


func _take_slot(cursor: Cursor, lock_in: bool) -> void:
	if cursor.locked or cursor.place != PLACE_TRAY:
		return
	if _slot_claimed_by_other(cursor):
		return
	cursor.place = PLACE_SLOT
	_update_cursor_visual(cursor)
	_update_slot_border()
	_refresh_legends()
	if lock_in:
		_lock_cursor(cursor)
		return
	SfxManager.play_ui_hover()
	_refresh_ready_state()


func _return_to_tray(cursor: Cursor) -> void:
	if cursor.locked or cursor.place != PLACE_SLOT:
		return
	cursor.place = PLACE_TRAY
	SfxManager.play_ui_hover()
	_update_cursor_visual(cursor)
	_update_slot_border()
	_refresh_legends()
	_refresh_ready_state()


# Only one cursor may hold the creature: another device asking for it while it
# is taken is simply ignored until the holder gives it back.
func _slot_claimed_by_other(cursor: Cursor) -> bool:
	for other in cursors:
		if other != cursor and other.place == PLACE_SLOT:
			return true
	return false


func _lock_cursor(cursor: Cursor) -> void:
	if cursor.locked or cursor.place != PLACE_SLOT:
		return
	if _slot_claimed_by_other(cursor):
		return
	SfxManager.play_ui_select()
	cursor.locked = true
	_show_selected()
	GameManager.p1_character_id = 1
	GameManager.p1_device = cursor.device
	# The lab has one player: make sure a previous session's second slot cannot
	# leave a device bound to a creature that is not there.
	GameManager.p2_character_id = 0
	GameManager.p2_device = null
	if cursor.device != null:
		print("Practice Range claimed by: %s" % cursor.device.display_name)
	_update_slot_border()
	_refresh_legends()
	_play_lock_feedback(cursor)
	_refresh_ready_state()


func _unlock_cursor(cursor: Cursor) -> void:
	if not cursor.locked:
		return
	SfxManager.play_ui_select()
	cursor.locked = false
	# Back to its own bay, so where the input is and what it has claimed stay
	# separate even as it lets go.
	cursor.place = PLACE_TRAY
	ready_label.visible = false
	GameManager.p1_character_id = 0
	GameManager.p1_device = null
	_update_cursor_visual(cursor)
	_update_slot_border()
	_refresh_legends()
	_refresh_ready_state()


func _show_selected() -> void:
	ready_label.visible = true
	ready_label.modulate = P1_ACCENT_COLOR
	ready_label.modulate.a = 0.0
	# Pops in rather than blinking on, so the confirmation visibly lands.
	ready_label.pivot_offset = ready_label.size * 0.5
	ready_label.scale = Vector2.ONE * selected_label_pop_scale
	var pop := create_tween()
	pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(ready_label, "scale", Vector2.ONE, selected_label_pop_duration)
	pop.parallel().tween_property(ready_label, "modulate:a", 1.0, selected_label_pop_duration * 0.6)


# The moment the creature is confirmed: the cursor punches up and settles while
# the SELECTED label pops in. Both use the project's springy TRANS_BACK pop, so
# confirming has somewhere to land instead of being a silent state change.
func _play_lock_feedback(cursor: Cursor) -> void:
	if is_instance_valid(cursor.node):
		var node := cursor.node
		node.pivot_offset = node.size * 0.5
		node.scale = Vector2.ONE * lock_punch_scale
		var punch := create_tween()
		punch.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		punch.tween_property(node, "scale", Vector2.ONE, lock_punch_duration)
	if is_instance_valid(cursor.icon):
		var icon := cursor.icon
		var icon_base := icon.scale
		icon.scale = icon_base * lock_punch_scale
		var icon_tween := create_tween()
		icon_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		icon_tween.tween_property(icon, "scale", icon_base, lock_punch_duration)


# ── Control legend ──
# The two legends follow one device: whichever one is on the creature, or -
# before anything is claimed - the device that joined most recently. That is the
# device the player who just pressed a button owns, so the controls appear the
# moment they join rather than only once they have found their way to the slot.

func _legend_cursor() -> Cursor:
	for cursor in cursors:
		if cursor.place == PLACE_SLOT:
			return cursor
	if cursors.is_empty():
		return null
	return cursors[cursors.size() - 1]


func _refresh_legends() -> void:
	var cursor := _legend_cursor()
	var device : PlayerInputDevice = null
	if cursor != null:
		device = cursor.device
	if device == _legend_device and _legends_visible == (device != null):
		return
	_legend_device = device
	_legends_visible = device != null
	legends.visible = _legends_visible
	if device == null:
		return
	for prompts in [screen_prompts, lab_prompts]:
		if prompts == null:
			continue
		prompts.set_tint(P1_ACCENT_COLOR)
		prompts.set_device(device)


# ── Visuals ──

func _update_cursor_visual(cursor: Cursor) -> void:
	var target : Vector2
	if cursor.place == PLACE_SLOT:
		target = _slot_position()
	else:
		target = _bay_cursor_position(cursor.bay_index)
	_slide_cursor(cursor, target)


# Cursors travel instead of teleporting, on the same springy TRANS_BACK beat the
# versus select screen uses. The icon is tweened alongside the square it sits in,
# so the drawn cursor moves as one piece.
func _slide_cursor(cursor: Cursor, target: Vector2) -> void:
	if not is_instance_valid(cursor.node) or not is_instance_valid(cursor.icon):
		return
	if cursor.slide != null and cursor.slide.is_valid():
		cursor.slide.kill()
	cursor.slide = create_tween()
	cursor.slide.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cursor.slide.tween_property(cursor.node, "position", target, CURSOR_SLIDE_SECONDS)
	cursor.slide.parallel().tween_property(
		cursor.icon, "position", target + (cursor_size * 0.5), CURSOR_SLIDE_SECONDS
	)


func _slot_position() -> Vector2:
	var centre := character_slot.position + character_slot.size * 0.5
	return centre - cursor_size * 0.5


# The tray row is centred inside the tray's own rect, and its bays are the
# scene's template panel, so both the row and the bay look come from the scene.
func _bay_rect(index: int) -> Rect2:
	var bay_size := tray_bay_template.size
	var count := maxi(cursors.size(), 1)
	var row_width := (count - 1) * tray_bay_spacing + bay_size.x
	var x := tray_area.position.x + (tray_area.size.x - row_width) * 0.5
	var y := tray_area.position.y + (tray_area.size.y - bay_size.y) * 0.5
	return Rect2(Vector2(x + index * tray_bay_spacing, y), bay_size)


func _bay_cursor_position(index: int) -> Vector2:
	var rect := _bay_rect(index)
	return rect.position + (rect.size - cursor_size) * 0.5


func _rebuild_bays() -> void:
	for child in tray_bays.get_children():
		tray_bays.remove_child(child)
		child.queue_free()
	for i in cursors.size():
		var rect := _bay_rect(i)
		var bay := tray_bay_template.duplicate() as Control
		if bay == null:
			continue
		bay.visible = true
		bay.position = rect.position
		bay.size = rect.size
		tray_bays.add_child(bay)


# The slot's border colour says whether the creature is held. Kept in the scene
# as two exported colours rather than hardcoded here.
func _update_slot_border() -> void:
	var style := character_slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	style.border_color = claimed_border_color if _claimed_cursor() != null else open_border_color


func _refresh_device_label() -> void:
	var cursor := _claimed_cursor()
	if cursor == null:
		cursor = _slot_cursor()
	if cursor == null or cursor.device == null:
		device_label.text = "PRESS A BUTTON TO JOIN"
		return
	device_label.text = "DEVICE: %s" % cursor.device.display_name


func _refresh_ready_state() -> void:
	var ready := _claimed_cursor() != null
	var was_visible := start_button.visible
	start_button.visible = ready
	# Popped in on the frame it first appears, on the same beat as the versus
	# screen and the main menu. Duck-typed, so a plain Button still works here.
	if ready and not was_visible and start_button.has_method("pop_in"):
		start_button.call("pop_in")


# The device holding the creature, if any.
func _claimed_cursor() -> Cursor:
	for cursor in cursors:
		if cursor.locked:
			return cursor
	return null


# The device sitting in the creature's slot, whether or not it has locked in.
func _slot_cursor() -> Cursor:
	for cursor in cursors:
		if cursor.place == PLACE_SLOT:
			return cursor
	return null


# ── Disconnects ──

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		return
	_created_joypad.erase(device_id)
	for cursor in cursors:
		if cursor.device == null:
			continue
		if cursor.device.kind == PlayerInputDevice.Kind.JOYPAD and cursor.device.device_id == device_id:
			_remove_cursor(cursor)
			return


func _remove_cursor(cursor: Cursor) -> void:
	if cursor.locked:
		ready_label.visible = false
		GameManager.p1_character_id = 0
		GameManager.p1_device = null

	cursors.erase(cursor)
	if is_instance_valid(cursor.node):
		cursor.node.queue_free()
	if is_instance_valid(cursor.icon):
		cursor.icon.queue_free()

	# Bays are the devices in join order, so the row closes up behind the one
	# that left instead of keeping an empty gap for it.
	for i in cursors.size():
		cursors[i].bay_index = i

	_rebuild_bays()
	_update_slot_border()
	_refresh_legends()
	_refresh_ready_state()


# ── Starting the lab ──

func _on_button_pressed() -> void:
	if _starting_match:
		return
	if not start_button.visible:
		return
	var cursor := _claimed_cursor()
	if cursor == null or cursor.device == null:
		return
	_starting_match = true
	SfxManager.play_ui_select()
	GameManager.p1_character_id = 1
	GameManager.p1_device = cursor.device
	GameManager.p2_character_id = 0
	GameManager.p2_device = null
	# The lab reads mode_id to know it is the single-player flow.
	GameManager.mode_id = 2
	GameManager.bind_player_inputs()
	SceneTransition.change_scene(LAB_SCENE)


# ── Per-device input resolution ──
# Same helpers the other select screen uses: a device answers either through its
# own keys (keyboard) or its d-pad/buttons and stick (controller).

func _device_just_pressed(device: PlayerInputDevice, action_name: String) -> bool:
	if device == null:
		return false
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return _keyboard_action_just_pressed(action_name, device.native_action_suffix)
	# A controller can answer with either the d-pad/button for this base or the
	# left stick pushed that way. Both are checked: reading buttons only meant
	# the stick could not move a cursor or confirm on this screen, even though
	# the same stick works in a fight.
	if _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name)):
		return true
	return _joy_axis_just_pressed(device.device_id, action_name)


# Select, plus Enter for a keyboard device: ui_accept also answers to a pad's A,
# which would double up with the device check above, so it is only consulted for
# a keyboard.
func _confirm_just_pressed(device: PlayerInputDevice) -> bool:
	if _device_just_pressed(device, "Normal"):
		return true
	if device == null or device.kind != PlayerInputDevice.Kind.KEYBOARD:
		return false
	return Input.is_action_just_pressed("ui_accept")


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
	if action_name == "Jump":
		return joy_jump_button
	return joy_normal_button


func _joy_button_just_pressed(device_id: int, button_index: int) -> bool:
	var key := "%d_%d" % [device_id, button_index]
	var pressed := Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed : bool = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed


# Stick equivalent of a d-pad press for the directional bases, edge detected the
# same way the button checks are. Shares GameManager's axis map and threshold so
# a stick tilt means the same thing here as it does in a fight.
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
