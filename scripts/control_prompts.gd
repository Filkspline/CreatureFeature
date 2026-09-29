class_name ControlPrompts
extends Control

# ──────────────────────────────────────────────────────────────────
#  ControlPrompts
#
#  A small strip of control buttons for one player's input scheme: the icon
#  for each button next to a label saying what it does. When reactive, it also
#  watches that player's real input and bounces the matching icon the moment
#  the button is pressed, so the prompt doubles as immediate feedback that the
#  press registered (and reinforces which physical button does what).
#
#  Used by the fight HUD, the pre-fight card select, the round-over draft, and
#  the player-select legend. All of them draw from the same icon sheet and the
#  same scheme detection, so a controller player sees controller buttons
#  everywhere and a keyboard player sees their own keys.
#
#  Every visual and timing value is exported, so each placement is tuned in
#  the scene rather than in code. Child icons/labels are built at runtime
#  because which ones exist depends on the scheme.

## Which buttons a prompt shows, and what they are called.
enum Preset {
	## Movement, Normal, Special, plus Jump where the scheme has an icon.
	FULL,
	## The two buttons a selection screen needs: Normal confirms, Special
	## backs out.
	SELECT_DESELECT,
}

enum Alignment { LEFT, CENTER, RIGHT }

@export_group("What to show")
## Player this prompt belongs to; picks up that player's device from
## GameManager unless a device is set explicitly.
@export var player_id : int = 1
@export var preset : Preset = Preset.FULL
## Force a scheme instead of detecting one, for checking a look without the
## matching hardware plugged in.
@export_enum("Detect", "WASD", "Arrows", "Controller") var scheme_override : int = 0
## Stack the entries downwards instead of along a row.
@export var vertical : bool = false
@export var alignment : Alignment = Alignment.LEFT

@export_group("Look")
## The sheet's frames are 100x100, so this is roughly pixels of icon per 100
## pixels of sheet.
@export var icon_scale : float = 0.22
## Distance between one entry and the next along the strip.
@export var entry_spacing : float = 56.0
## Gap between an icon and its label.
@export var label_gap : float = 4.0
@export var font_size : int = 12
@export var outline_size : int = 2
@export var icon_color : Color = Color(1, 1, 1, 1)
@export var label_color : Color = Color(1, 1, 1, 1)
@export var icon_modulate_alpha : float = 0.85

@export_group("Press feedback")
## Whether to watch this player's input and bounce icons. Off for a legend
## that is purely a reference.
@export var reactive : bool = true
@export var bounce_scale : float = 1.45
@export var bounce_duration : float = 0.2
@export var bounce_transition : Tween.TransitionType = Tween.TRANS_BACK
@export var bounce_ease : Tween.EaseType = Tween.EASE_OUT

const SHEET := preload("res://assets/controls.tres")
const FRAME_SIZE := 100.0
const UI_FONT := preload("res://assets/card_assets/m3x6.ttf")

## Entry tables: [action key, label]. The action key indexes ControlScheme's
## frame tables, so adding a row here is all a new prompt needs.
##
## Movement is deliberately absent: every player already knows how to move,
## and the cluster icon is the widest thing a prompt could carry. The action
## buttons are what a prompt is for.
const ENTRIES := {
	Preset.FULL: [
		["normal", "Normal"],
		["special", "Special"],
		["jump", "Jump"],
	],
	Preset.SELECT_DESELECT: [
		["normal", "Select"],
		["special", "Deselect"],
	],
}

var _scheme : int = ControlScheme.Scheme.WASD
var _device : PlayerInputDevice = null
var _device_is_explicit : bool = false
# [{"icon": AnimatedSprite2D, "base_scale": Vector2, "action": StringName}]
var _rows : Array[Dictionary] = []


func _ready() -> void:
	_refresh()


func _process(_delta: float) -> void:
	if not reactive or _rows.is_empty():
		return
	for row in _rows:
		var action: StringName = row["action"]
		if action != &"" and Input.is_action_just_pressed(action):
			_bounce(row["icon"])


## Uses this device instead of whatever the player slot is holding, for
## screens where the choice has not been locked in yet (player select).
func set_device(device: PlayerInputDevice) -> void:
	_device = device
	_device_is_explicit = true
	_refresh()


## Back to following the player slot's claimed device.
func clear_device_override() -> void:
	_device = null
	_device_is_explicit = false
	_refresh()


func set_tint(color: Color) -> void:
	icon_color = color
	label_color = color
	_refresh()


func set_player(new_player_id: int) -> void:
	player_id = new_player_id
	if not _device_is_explicit:
		_refresh()


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()

	_scheme = _resolve_scheme()
	var slot_suffix := "P%d" % player_id
	var icon_size := FRAME_SIZE * icon_scale

	# Entries first as measured blocks, then laid out, so alignment can be
	# applied once the total length is known.
	var blocks : Array[Dictionary] = []
	for entry in ENTRIES.get(preset, ENTRIES[Preset.FULL]):
		var action_key: String = entry[0]
		var frame := ControlScheme.frame_for(_scheme, action_key)
		if frame < 0:
			continue
		var label_text: String = entry[1]
		var label_width := UI_FONT.get_string_size(
			label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		var block_length := icon_size + label_gap + label_width
		blocks.append({
			"frame": frame,
			"text": label_text,
			"length": block_length,
			"action": ControlScheme.input_action_for(action_key, slot_suffix),
		})
	if blocks.is_empty():
		return

	var total := 0.0
	for i in blocks.size():
		total += blocks[i]["length"]
		if i < blocks.size() - 1:
			total += entry_spacing

	# Alignment inside the node's box: a row shifts along its own axis, a
	# column shifts sideways to sit left/centre/right.
	var extent := total
	if vertical:
		extent = 0.0
		for block in blocks:
			extent = maxf(extent, block["length"])
	var offset := 0.0
	if alignment == Alignment.CENTER:
		offset = (size.x - extent) * 0.5
	elif alignment == Alignment.RIGHT:
		offset = size.x - extent

	var cursor := 0.0
	if not vertical:
		cursor = offset
	for block in blocks:
		var icon := AnimatedSprite2D.new()
		icon.sprite_frames = SHEET
		icon.frame = block["frame"]
		icon.scale = Vector2.ONE * icon_scale
		var icon_color_now := icon_color
		icon_color_now.a *= icon_modulate_alpha
		icon.modulate = icon_color_now

		var label := Label.new()
		label.text = block["text"]
		label.add_theme_font_override("font", UI_FONT)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_constant_override("outline_size", outline_size)
		label.add_theme_color_override("font_color", label_color)

		if vertical:
			icon.position = Vector2(offset + icon_size * 0.5, cursor + icon_size * 0.5)
			label.position = Vector2(offset + icon_size + label_gap, cursor + icon_size * 0.5 - font_size * 0.5)
			cursor += icon_size + entry_spacing
		else:
			icon.position = Vector2(cursor + icon_size * 0.5, icon_size * 0.5)
			label.position = Vector2(cursor + icon_size + label_gap, icon_size * 0.5 - font_size * 0.5)
			cursor += block["length"] + entry_spacing

		add_child(icon)
		add_child(label)
		_rows.append({
			"icon": icon,
			"base_scale": Vector2.ONE * icon_scale,
			"action": block["action"],
		})


func _resolve_scheme() -> int:
	if scheme_override > 0:
		return scheme_override - 1
	if _device == null:
		_device = GameManager.p1_device if player_id == 1 else GameManager.p2_device
	return ControlScheme.scheme_for(_device)


func _bounce(icon: AnimatedSprite2D) -> void:
	if not is_instance_valid(icon):
		return
	var row := _row_for(icon)
	if row.is_empty():
		return
	var base: Vector2 = row["base_scale"]
	var tween := create_tween()
	tween.set_trans(bounce_transition).set_ease(bounce_ease)
	tween.tween_property(icon, "scale", base * bounce_scale, bounce_duration * 0.5)
	tween.tween_property(icon, "scale", base, bounce_duration * 0.5)


func _row_for(icon: AnimatedSprite2D) -> Dictionary:
	for row in _rows:
		if row["icon"] == icon:
			return row
	return {}
