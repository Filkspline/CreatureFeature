extends Control

# ──────────────────────────────────────────────────────────────────
#  SinglePlayerTutorial
#
#  The Practice Range's instruction card: what the buttons do, how the
#  practice menu and its cards work, and what the damage readout means.
#
#  Every key name printed here is read back out of the keyboard layouts
#  GameManager captured for the layout player 1 actually claimed, and every
#  icon comes from the same control sheet and the same ControlScheme mapping
#  the select screen and the pause menu already use. Nothing is hardcoded, so
#  the text cannot drift out of step with project.godot's InputMap, and a
#  keyboard player who joined on the arrow-key layout sees their own keys
#  rather than WASD's.
#
#  Only the text and the icon frames are derived here: the panel, the fonts,
#  the colours, the column widths and the card row's anchor are all set in
#  single_player_tutorial_background.tscn, where they can be seen and edited
#  by selecting a node.

## Control-sheet icons for the action buttons, in a strip under the controls
## heading. Frames are chosen per device in _ready().
@export var movement_icon : AnimatedSprite2D
@export var normal_icon : AnimatedSprite2D
@export var special_icon : AnimatedSprite2D
@export var jump_icon : AnimatedSprite2D

## The two instruction columns, as whole multi-line blocks. One label each
## rather than a node per row: the font is a fixed-width pixel face, so the
## columns line up on spaces the same way they do in the scene, and a single
## label per column keeps the row spacing tunable in one place.
@export var controls_text : Label
@export var menus_text : Label

## Keyboard layout used when no device has been claimed (opening the lab scene
## directly in the editor instead of through the select screen).
@export var fallback_keyboard_suffix : String = "P1"


func _ready() -> void:
	var device := GameManager.p1_device
	_apply_icons(device)
	if device != null and device.kind == PlayerInputDevice.Kind.JOYPAD:
		_fill_pad_text()
	else:
		_fill_keyboard_text(device)


# ── Icons ──
# Same sheet, same rows and same frames the rest of the game draws these
# buttons with. A scheme with no icon for an action (-1) hides that node
# rather than showing another row's art: ControlScheme is explicit that a
# keyboard row has no jump icon.
func _apply_icons(device: PlayerInputDevice) -> void:
	var scheme : int = ControlScheme.scheme_for(device)
	_set_icon(movement_icon, scheme, "movement")
	_set_icon(normal_icon, scheme, "normal")
	_set_icon(special_icon, scheme, "special")
	_set_icon(jump_icon, scheme, "jump")


func _set_icon(icon : AnimatedSprite2D, scheme : int, action_key : String) -> void:
	if icon == null:
		return
	var frame : int = ControlScheme.frame_for(scheme, action_key)
	icon.visible = frame >= 0
	if frame >= 0:
		icon.frame = frame


# ── Keyboard text ──
func _fill_keyboard_text(device: PlayerInputDevice) -> void:
	var layout := fallback_keyboard_suffix
	if device != null and device.native_action_suffix != "":
		layout = device.native_action_suffix

	var back := _keys("Left", layout)
	var forward := _keys("Right", layout)
	set_label_text(controls_text, _lines([
		"%-9s%s  %s" % ["MOVE", back, forward],
		"%-9s%s" % ["JUMP", _keys("Jump", layout)],
		"%-9s%s" % ["NORMAL", _keys("Normal", layout)],
		"%-9s%s" % ["SPECIAL", _keys("Special", layout)],
		"%-9s%s" % ["CROUCH", _keys("Down", layout)],
		"%-9s%s" % ["BLOCK", "hold %s" % back],
		"%-9s%s" % ["DASH", "tap %s or %s twice" % [back, forward]],
	]))

	set_label_text(menus_text, _lines([
		"%-9s%s" % ["OPEN", "Tab or Enter"],
		"%-9s%s  %s" % ["MOVE", _keys("Up", layout), _keys("Down", layout)],
		"%-9s%s  %s" % ["PICK", back, forward],
		"%-9s%s" % ["TAKE", "Enter"],
		"%-9s%s" % ["REMOVE", _keys("Special", layout)],
		"%-9s%s" % ["CLOSE", "Back button"],
		"%-9s%s" % ["DAMAGE", "shows each hit"],
		"%-9s%s" % ["DUMMY", "cycles its own"],
		"%-9s%s" % ["", "block: mids either,"],
		"%-9s%s" % ["", "lows crouch only,"],
		"%-9s%s" % ["", "overheads stand only"],
	]))


# The keys a base action actually answers to on this layout, straight out of
# the captured InputMap events, so the tutorial can never name a key the
# project no longer binds.
func _keys(base : String, layout : String) -> String:
	var names : Array[String] = []
	for event in GameManager.keyboard_layouts.get(layout, {}).get(base, []):
		var key_event := event as InputEventKey
		if key_event == null:
			continue
		var code := key_event.physical_keycode
		if code == KEY_NONE:
			code = key_event.keycode
		if code == KEY_NONE:
			continue
		var key_name := OS.get_keycode_string(code)
		if key_name != "" and not names.has(key_name):
			names.append(key_name)
	return " / ".join(PackedStringArray(names)) if not names.is_empty() else "-"


# ── Controller text ──
# Every pad button named here is the one GameManager binds for a pad's slot
# (see _add_joypad_events), plus the pad side of the practice menu's own
# toggle. A pad's own button names are what the control sheet draws, so the
# strip above stays honest too.
func _fill_pad_text() -> void:
	set_label_text(controls_text, _lines([
		"%-9s%s" % ["MOVE", "stick  d-pad"],
		"%-9s%s" % ["JUMP", "X"],
		"%-9s%s" % ["NORMAL", "A"],
		"%-9s%s" % ["SPECIAL", "B"],
		"%-9s%s" % ["CROUCH", "d-pad down"],
		"%-9s%s" % ["BLOCK", "hold back"],
		"%-9s%s" % ["DASH", "tap a way twice"],
	]))

	set_label_text(menus_text, _lines([
		"%-9s%s" % ["OPEN", "Y"],
		"%-9s%s" % ["MOVE", "d-pad  up  down"],
		"%-9s%s" % ["PICK", "d-pad  left  right"],
		"%-9s%s" % ["TAKE", "A"],
		"%-9s%s" % ["REMOVE", "B"],
		"%-9s%s" % ["CLOSE", "Back button"],
		"%-9s%s" % ["DAMAGE", "shows each hit"],
		"%-9s%s" % ["DUMMY", "cycles its own"],
		"%-9s%s" % ["", "block: mids either,"],
		"%-9s%s" % ["", "lows crouch only,"],
		"%-9s%s" % ["", "overheads stand only"],
	]))


func set_label_text(label : Label, text : String) -> void:
	if label:
		label.text = text


# The rows of a column joined into the one multi-line label that draws them.
# The conversion is explicit because String.join() takes a PackedStringArray and
# these callers build plain arrays.
func _lines(rows : Array) -> String:
	return "\n".join(PackedStringArray(rows))
