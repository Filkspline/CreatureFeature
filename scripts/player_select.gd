extends Control

# ──────────────────────────────────────────────────────────────────
#  PlayerSelect (boot screen character + device select)
#
#  Device model, rewritten:
#
#  Both slots now start with a real keyboard device already assigned
#  (P1 = "P1" InputMap actions, P2 = "P2" InputMap actions) the moment
#  this scene loads. There is no "press a button to join" step for
#  keyboards any more - two people can sit down on WASD and arrow keys
#  and both cursors are already live. This is what was actually wrong
#  before: p1_device/p2_device started as null and nothing drove a
#  cursor until a join press happened, which is why P2's keyboard
#  looked dead if nobody knew to press NormalP2 first.
#
#  A connected controller can still take over a slot, but only by
#  replacing that slot's keyboard device, and only while that slot is
#  (a) still on its default keyboard and (b) not locked in yet. A slot
#  whose device.kind is already JOYPAD is not "open" any more, so a
#  second controller (or the same one firing twice) can never land on
#  a slot that's already controller-owned - that's what was letting
#  one controller end up driving both cursors. This also gives the
#  "only one cursor in a slot at a time" guarantee for free: each slot
#  has exactly one device reference, and claiming a slot means
#  swapping that reference, never adding a second source on top of it.
#
#  If a claimed controller disconnects mid-select (and its slot isn't
#  locked yet), that slot falls back to its default keyboard rather
#  than going back to null, so the slot never goes dead.
#
#  Locking in still routes both players through the same _lock_in(),
#  and picks/devices are written to GameManager for the fight scene to
#  read. Once start_button is visible (both locked), either player's
#  confirm press - keyboard or controller - triggers start, not just a
#  mouse click on the button.

const FIGHT_SCENE := "res://scenes/pre_fight_upgrade_screen.tscn"

const P1_ACCENT_COLOR := Color(1.0, 1.0, 1.0) # white
const P2_ACCENT_COLOR := Color(0.79607844, 0.85882354, 0.9882353) # cbdbfc

# -1 = Character 1
#  0 = Neutral
#  1 = Character 2
const SELECTION_MIN := -1
const SELECTION_MAX := 1

@export var joy_normal_button : int = JOY_BUTTON_A # confirm / join
@export var joy_jump_button : int = JOY_BUTTON_X
@export var joy_special_button : int = JOY_BUTTON_B

const JOY_DIRECTION_BUTTONS := {
	"Left": JOY_BUTTON_DPAD_LEFT,
	"Right": JOY_BUTTON_DPAD_RIGHT,
	"Up": JOY_BUTTON_DPAD_UP,
	"Down": JOY_BUTTON_DPAD_DOWN,
}

@onready var start_button = $Button

@onready var p1_cursor = $Cursors/Player1
@onready var p2_cursor = $Cursors/Player2

@onready var character1_selected = $Characters/Character1/SelectedLabel
@onready var character2_selected = $Characters/Character2/SelectedLabel

@onready var character1 = $Characters/Character1
@onready var character2 = $Characters/Character2

@onready var p1_device_label : Label = $DeviceLabels/P1DeviceLabel
@onready var p2_device_label : Label = $DeviceLabels/P2DeviceLabel

var p1_selection := 0
var p2_selection := 0

var p1_locked := false
var p2_locked := false

var p1_device : PlayerInputDevice
var p2_device : PlayerInputDevice

var p1_neutral_position: Vector2
var p2_neutral_position: Vector2

# Edge-detection state for raw joypad polling ("device_id_button" -> was
# it down last frame). Needed because Input.is_joy_button_pressed only
# gives a held/not-held snapshot - there's no built in
# is_joy_button_just_pressed, and menu navigation needs the edge, not
# the hold, or the cursor would fly across every held frame.
var _joy_button_prev_state : Dictionary = {}
var _claimed_joypad_ids : Dictionary = {} # device_id -> true once claimed by a slot


func _ready():
	GameManager.reset_player_select()

	p1_neutral_position = p1_cursor.position
	p2_neutral_position = p2_cursor.position
	start_button.visible = false

	p1_device = _make_default_keyboard(1)
	p2_device = _make_default_keyboard(2)

	update_cursors()
	_refresh_device_labels()

	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(_delta):
	_handle_joypad_join_input()

	_handle_slot_input(1)
	_handle_slot_input(2)


func check_both_locked():
	if p1_locked and p2_locked:
		start_button.visible = true


# ── Joining: a controller taking over a slot's default keyboard ──

func _handle_joypad_join_input() -> void:
	for joy_id in Input.get_connected_joypads():
		if _claimed_joypad_ids.get(joy_id, false):
			continue
		if _joy_button_just_pressed(joy_id, joy_normal_button):
			_claim_open_slot_for_joypad(joy_id)


func _claim_open_slot_for_joypad(joy_id : int) -> void:
	var slot := _find_open_slot_for_joypad()
	if slot == 0:
		# Both slots are either locked or already controller-owned.
		# Nowhere for this controller to go, ignore the press.
		return

	_claim_device(PlayerInputDevice.make_joypad(joy_id), slot)


# A slot is open to a new controller only while it's still on its
# default keyboard and hasn't locked in yet. Once a controller owns a
# slot (kind == JOYPAD) or the slot is locked, it's no longer up for
# grabs - this is what stops one controller from ever driving both
# cursors, and stops a second controller from stealing an owned slot.
func _find_open_slot_for_joypad() -> int:
	if not p1_locked and p1_device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return 1
	if not p2_locked and p2_device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return 2
	return 0


func _claim_device(device : PlayerInputDevice, slot : int) -> void:
	if device.kind == PlayerInputDevice.Kind.JOYPAD:
		_claimed_joypad_ids[device.device_id] = true

	if slot == 1:
		p1_device = device
	else:
		p2_device = device

	_refresh_device_labels()


func _make_default_keyboard(slot : int) -> PlayerInputDevice:
	if slot == 1:
		return PlayerInputDevice.make_keyboard("Keyboard (WASD)", "P1")
	return PlayerInputDevice.make_keyboard("Keyboard (Arrows)", "P2")


func _on_joy_connection_changed(device_id : int, connected : bool) -> void:
	if not connected:
		_claimed_joypad_ids.erase(device_id)
		_release_slot_if_disconnected(p1_device, device_id, 1)
		_release_slot_if_disconnected(p2_device, device_id, 2)

	_refresh_device_labels()


# If the controller driving a not-yet-locked slot disconnects, that
# slot falls back to its default keyboard instead of going dead, so
# there is always a working cursor in every unlocked slot.
func _release_slot_if_disconnected(device : PlayerInputDevice, disconnected_id : int, slot : int) -> void:
	if device == null or device.kind != PlayerInputDevice.Kind.JOYPAD:
		return
	if device.device_id != disconnected_id:
		return
	if slot == 1 and not p1_locked:
		p1_device = _make_default_keyboard(1)
	elif slot == 2 and not p2_locked:
		p2_device = _make_default_keyboard(2)


func _refresh_device_labels() -> void:
	p1_device_label.text = _device_status_text(p1_device)
	p2_device_label.text = _device_status_text(p2_device)


func _device_status_text(device : PlayerInputDevice) -> String:
	if device == null:
		return "PRESS A BUTTON TO JOIN"
	return "DEVICE: %s" % device.display_name


# ── Per slot navigation / lock-in ──

func _handle_slot_input(slot : int) -> void:
	var device = p1_device if slot == 1 else p2_device
	if device == null:
		return

	var locked = p1_locked if slot == 1 else p2_locked
	if locked:
		# Either player can press start once both are locked in, not
		# just whoever clicks the on-screen button.
		if start_button.visible and _device_just_pressed(device, "Normal"):
			_on_button_pressed()
		return

	if _device_just_pressed(device, "Left"):
		_move_selection(slot, -1)
	elif _device_just_pressed(device, "Right"):
		_move_selection(slot, 1)

	if _device_just_pressed(device, "Normal"):
		_lock_in(slot)


func _move_selection(slot : int, delta : int) -> void:
	var current = p1_selection if slot == 1 else p2_selection
	var other_locked = p2_locked if slot == 1 else p1_locked
	var other_selection = p2_selection if slot == 1 else p1_selection

	var new_selection = clampi(current + delta, SELECTION_MIN, SELECTION_MAX)
	if new_selection == current:
		return
	# Don't let an unlocked cursor sit on top of the other player's locked character
	if other_locked and new_selection == other_selection:
		return

	if slot == 1:
		p1_selection = new_selection
		update_p1_cursor()
	else:
		p2_selection = new_selection
		update_p2_cursor()


func _lock_in(slot : int) -> void:
	var selection = p1_selection if slot == 1 else p2_selection
	if selection == 0:
		return

	if slot == 1:
		p1_locked = true
	else:
		p2_locked = true

	_show_selected_label(selection, slot)
	_store_character_choice(slot, selection)
	print("P%d locked in character: %d" % [slot, selection])
	check_both_locked()


func _show_selected_label(selection : int, slot : int) -> void:
	var label = character1_selected if selection == -1 else character2_selected
	label.visible = true
	label.modulate = P1_ACCENT_COLOR if slot == 1 else P2_ACCENT_COLOR


func _store_character_choice(slot : int, selection : int) -> void:
	var character_id = 1 if selection == -1 else 2
	if slot == 1:
		GameManager.p1_character_id = character_id
	else:
		GameManager.p2_character_id = character_id


func update_cursors():
	update_p1_cursor()
	update_p2_cursor()


func update_p1_cursor():
	match p1_selection:
		-1:
			p1_cursor.position = get_character_position(character1, p1_cursor)
		0:
			p1_cursor.position = p1_neutral_position
		1:
			p1_cursor.position = get_character_position(character2, p1_cursor)


func update_p2_cursor():
	match p2_selection:
		-1:
			p2_cursor.position = get_character_position(character1, p2_cursor)
		0:
			p2_cursor.position = p2_neutral_position
		1:
			p2_cursor.position = get_character_position(character2, p2_cursor)


func get_character_position(character: Control, cursor: Control) -> Vector2:
	var character_center = character.position + character.size / 2.0
	return character_center - cursor.size / 2.0


# ── Raw per-device input helpers ──
# Keyboard slots read the same named InputMap actions as before (each
# key set is already unambiguous on its own). Joypad slots read the
# claimed device's raw button state directly, filtered by device id, so
# two controllers plugged in at once can never bleed into each other.

func _device_just_pressed(device : PlayerInputDevice, action_name : String) -> bool:
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return Input.is_action_just_pressed(action_name + device.native_action_suffix)
	return _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name))


func _joy_button_for_action(action_name : String) -> int:
	if JOY_DIRECTION_BUTTONS.has(action_name):
		return JOY_DIRECTION_BUTTONS[action_name]
	if action_name == "Special":
		return joy_special_button
	if action_name == "Jump":
		return joy_jump_button
	return joy_normal_button


func _joy_button_just_pressed(device_id : int, button_index : int) -> bool:
	var key = "%d_%d" % [device_id, button_index]
	var pressed = Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed


# ── Committing controller bindings for the fight scene ──
# Keyboard actions are already correctly bound in the InputMap and
# never touched. A claimed controller gets its device id written into
# that slot's Left/Right/Up/Down/Jump/Normal/Special actions right
# before we leave this scene, so every other script downstream (Player,
# the pre fight draft, etc) can keep using plain
# Input.is_action_just_pressed("LeftP1") without knowing anything about
# devices at all. A slot still sitting on its default keyboard is a
# no-op here, since the keyboard actions were never touched.

func _bind_device_to_slot(device : PlayerInputDevice, slot : int) -> void:
	if device == null or device.kind != PlayerInputDevice.Kind.JOYPAD:
		return

	var suffix = "P%d" % slot
	for action_name in JOY_DIRECTION_BUTTONS:
		_rebind_joypad_button(action_name + suffix, device.device_id, JOY_DIRECTION_BUTTONS[action_name])
	_rebind_joypad_button("Jump" + suffix, device.device_id, joy_jump_button)
	_rebind_joypad_button("Normal" + suffix, device.device_id, joy_normal_button)
	_rebind_joypad_button("Special" + suffix, device.device_id, joy_special_button)


func _rebind_joypad_button(action : StringName, device_id : int, button_index : int) -> void:
	if not InputMap.has_action(action):
		push_warning("player_select: InputMap is missing action '%s', skipping controller bind" % action)
		return

	# Only clear existing joypad events - keyboard bindings for this
	# action are left completely alone.
	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventJoypadButton:
			InputMap.action_erase_event(action, existing_event)

	var joy_event := InputEventJoypadButton.new()
	joy_event.device = device_id
	joy_event.button_index = button_index
	InputMap.action_add_event(action, joy_event)


func _on_button_pressed() -> void:
	_bind_device_to_slot(p1_device, 1)
	_bind_device_to_slot(p2_device, 2)
	GameManager.p1_device = p1_device
	GameManager.p2_device = p2_device
	SceneTransition.change_scene(FIGHT_SCENE)
