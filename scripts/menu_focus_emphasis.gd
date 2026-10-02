class_name MenuFocusEmphasis
extends Node

# ──────────────────────────────────────────────────────────────────
#  MenuFocusEmphasis
#
#  Grows the text of whichever entry currently has focus, so a menu's
#  selection is obvious at a glance and not only by where the pointer sits.
#  The entry that lost focus eases back to its base size, so moving the
#  selection reads as one entry growing while the previous one settles.
#
#  Place one in a menu scene (the main menu and the pause menu both do, next
#  to their SelectionPointer) and point it at the menu's button list with
#  register_buttons(). It follows focus from there, exactly like the pointer
#  does, so the menu script needs no focus bookkeeping of its own.
#
#  The room the grown text needs is reserved up front, before anything
#  animates: every entry gets a custom_minimum_size big enough for the focused
#  size, so a VBoxContainer never re-flows as the selection moves. Only the
#  text animates, and the pointer's target stays where it is.

@export_group("Emphasis")
## How much bigger the focused entry's text gets than the rest.
@export var focused_font_scale : float = 1.35
@export var emphasis_duration : float = 0.16
## Same springy pop the cards and the selection pointer use.
@export var emphasis_transition : Tween.TransitionType = Tween.TRANS_BACK
@export var emphasis_ease : Tween.EaseType = Tween.EASE_OUT

@export_group("Reserved space")
## Slack added around the widest grown label when reserving room for it.
@export var width_padding : float = 28.0
@export var height_padding : float = 10.0

@export_group("Mouse")
## Hovering an entry selects it, so the mouse, the pointer and the text
## emphasis can never disagree about what is selected.
@export var hover_selects : bool = true

# Keys are Button, values are that button's authored font size.
var _base_font_sizes : Dictionary = {}
# Keys are Button, values are the Tween currently animating that button.
var _tweens : Dictionary = {}
var _emphasised : Button = null


func _ready() -> void:
	# Runs while the tree is paused too: the pause menu is one of the two
	# menus that use this, and its buttons are PROCESS_MODE_ALWAYS for the
	# same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Points this at a menu's button list. Call it from the menu's _ready(),
## after the menu has grabbed focus on its default entry.
func register_buttons(buttons: Array) -> void:
	_base_font_sizes.clear()
	for entry in buttons:
		var button := entry as Button
		if button == null:
			continue
		_base_font_sizes[button] = _font_size_of(button)
		button.focus_entered.connect(_on_button_focused.bind(button))
		if hover_selects:
			button.mouse_entered.connect(_on_button_hovered.bind(button))
	_reserve_space()
	# If something already holds focus (a menu selects its first entry in
	# _ready), start it emphasised immediately rather than waiting for the
	# next focus change.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button and _base_font_sizes.has(focus):
		_emphasise(focus as Button)


func _on_button_focused(button: Button) -> void:
	_emphasise(button)


func _on_button_hovered(button: Button) -> void:
	button.grab_focus()


func _emphasise(button: Button) -> void:
	if button == _emphasised or not _base_font_sizes.has(button):
		return
	var previous := _emphasised
	_emphasised = button
	if previous != null and _base_font_sizes.has(previous):
		_tween_font(previous, _base_size_of(previous))
	_tween_font(button, _focused_size_of(button))


func _tween_font(button: Button, target_size: int) -> void:
	var existing := _tweens.get(button) as Tween
	if existing:
		existing.kill()
	var tween := create_tween()
	_tweens[button] = tween
	tween.set_trans(emphasis_transition).set_ease(emphasis_ease)
	tween.tween_property(button, "theme_override_font_sizes/font_size", target_size, emphasis_duration)


func _base_size_of(button: Button) -> int:
	return int(_base_font_sizes.get(button, _font_size_of(button)))


func _focused_size_of(button: Button) -> int:
	return int(round(float(_base_size_of(button)) * focused_font_scale))


func _font_size_of(button: Button) -> int:
	var size := button.get_theme_font_size("font_size")
	return size if size > 0 else 16


# Gives every entry room for the widest grown label and the tallest grown line,
# so growing one entry's text can't resize the list around it.
func _reserve_space() -> void:
	var widest := 0.0
	var tallest := 0.0
	for entry in _base_font_sizes.keys():
		var button := entry as Button
		if button == null:
			continue
		# Typed explicitly: the key came out of a Dictionary, so the value is
		# untyped until it is cast, and an inferred local would not compile.
		var font : Font = button.get_theme_font("font")
		if font == null:
			continue
		var grown_size := _focused_size_of(button)
		widest = maxf(widest, font.get_string_size(
			button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, grown_size
		).x)
		tallest = maxf(tallest, font.get_height(grown_size))
	if widest <= 0.0 or tallest <= 0.0:
		return
	for entry in _base_font_sizes.keys():
		var button := entry as Button
		if button == null:
			continue
		var minimum : Vector2 = button.custom_minimum_size
		button.custom_minimum_size = Vector2(
			maxf(minimum.x, widest + width_padding),
			maxf(minimum.y, tallest + height_padding)
		)
