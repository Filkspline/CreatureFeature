extends Control

# ──────────────────────────────────────────────────────────────────
#  SinglePlayerTutorial
#
#  The Practice Range's control card: the buttons, the practice menu and its
#  cards, in as few lines as will fit on screen.
#
#  The four action buttons are shown as ICONS from the project's own control
#  sheet, chosen per device through ControlScheme - the same art the select
#  screen and the pause menu draw them with. That is deliberate on two counts:
#  the keyboard's attack keys are development placeholders, so spelling them
#  out would teach a player keys that mean nothing outside this build; and an
#  icon shows whatever input that player actually joined with (the WASD row,
#  the arrow-key row, or a pad) instead of assuming WASD.
#
#  Everything that IS worth naming - movement, jump, crouch, block, dash and
#  the menu keys - is read back out of the keyboard layouts GameManager
#  captured for the layout that player actually claimed, so the text can never
#  name a key the project no longer binds.
#
#  Nothing here is hardcoded to one input type: _refresh() rebuilds all of it
#  from GameManager.p1_device, and _process() rebuilds it again if that device
#  ever changes.

## The four icon slots, one per action button. The whole item is hidden when
## the player's scheme has no art for it - a keyboard row has no jump key icon -
## so the row closes up instead of leaving a caption under nothing.
@export var movement_item : Control
@export var normal_item : Control
@export var special_item : Control
@export var jump_item : Control

@export var movement_icon : AnimatedSprite2D
@export var normal_icon : AnimatedSprite2D
@export var special_icon : AnimatedSprite2D
@export var jump_icon : AnimatedSprite2D

## The two instruction columns, as whole multi-line blocks. One label each
## rather than a node per row: the font is a fixed-width pixel face, so the
## columns line up on spaces, and each column's spacing stays tunable in one
## place.
@export var controls_text : Label
@export var menus_text : Label

## Keyboard layout used when no device has been claimed (opening the lab scene
## directly in the editor rather than through the select screen).
@export var fallback_keyboard_suffix : String = "P1"

## The device this card was last built for. Compared every frame so a player
## who goes back through input select and rejoins with something else does not
## come back to a card describing their old device.
var _shown_device : PlayerInputDevice = null


func _ready() -> void:
	_refresh()


func _process(_delta : float) -> void:
	# A reference comparison per frame, in exchange for the card never being
	# able to fall out of step with the device that is actually playing.
	if GameManager.p1_device != _shown_device:
		_refresh()


func _refresh() -> void:
	var device := GameManager.p1_device
	_shown_device = device
	if device != null and device.kind == PlayerInputDevice.Kind.JOYPAD:
		_fill_pad_text()
	else:
		_fill_keyboard_text(device)
	_apply_icons(device)


# ── Icons ──
# Same sheet, same rows and same frames the rest of the game draws these
# buttons with. A scheme with no frame for an action (-1) hides that item
# outright: ControlScheme is explicit that a keyboard row has no jump icon, and
# for those players the jump line moves into the text column instead.
func _apply_icons(device: PlayerInputDevice) -> void:
	var scheme : int = ControlScheme.scheme_for(device)
	_set_icon(movement_item, movement_icon, scheme, "movement")
	_set_icon(normal_item, normal_icon, scheme, "normal")
	_set_icon(special_item, special_icon, scheme, "special")
	_set_icon(jump_item, jump_icon, scheme, "jump")


func _set_icon(item : Control, icon : AnimatedSprite2D, scheme : int, action_key : String) -> void:
	var frame : int = ControlScheme.frame_for(scheme, action_key)
	var has_icon := frame >= 0
	if item:
		item.visible = has_icon
	if icon:
		icon.visible = has_icon
		if has_icon:
			icon.frame = frame


# ── Keyboard text ──
func _fill_keyboard_text(device: PlayerInputDevice) -> void:
	var layout := fallback_keyboard_suffix
	if device != null and device.native_action_suffix != "":
		layout = device.native_action_suffix

	var left := _keys("Left", layout)
	var right := _keys("Right", layout)
	set_label_text(controls_text, _lines([
		"%-8s%s  %s" % ["MOVE", left, right],
		"%-8s%s" % ["JUMP", _keys("Jump", layout)],
		"%-8s%s" % ["CROUCH", _keys("Down", layout)],
		"%-8s%s" % ["BLOCK", "hold %s" % left],
		"%-8s%s" % ["DASH", "tap %s or %s twice" % [left, right]],
	]))

	set_label_text(menus_text, _lines([
		"%-8s%s" % ["MENU", "Tab or Enter"],
		"%-8s%s  %s" % ["PICK", left, right],
		"%-8s%s" % ["TAKE", "Enter"],
		"%-8s%s" % ["REMOVE", "Special"],
		"%-8s%s" % ["CLOSE", "Back"],
	]))


# The keys a base action actually answers to on this layout, straight out of
# the captured InputMap events, so the card can never name a key the project no
# longer binds.
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
# toggle. Move, jump, normal and special are the icons above, so naming them
# again here would only pad the column out.
func _fill_pad_text() -> void:
	set_label_text(controls_text, _lines([
		"%-8s%s" % ["CROUCH", "d-pad down"],
		"%-8s%s" % ["BLOCK", "hold back"],
		"%-8s%s" % ["DASH", "tap a way twice"],
	]))

	set_label_text(menus_text, _lines([
		"%-8s%s" % ["MENU", "Y"],
		"%-8s%s" % ["PICK", "d-pad  left  right"],
		"%-8s%s" % ["TAKE", "A"],
		"%-8s%s" % ["REMOVE", "B"],
		"%-8s%s" % ["CLOSE", "Back"],
	]))


func set_label_text(label : Label, text : String) -> void:
	if label:
		label.text = text


# The rows of a column joined into the one multi-line label that draws them.
# The conversion is explicit because String.join() takes a PackedStringArray and
# these callers build plain arrays.
func _lines(rows : Array) -> String:
	return "\n".join(PackedStringArray(rows))
