extends Control

# Shows what each button does for one player's chosen control scheme, on the
# pause menu. Icons come from the same sheet, and the same device -> row
# mapping, that the player-select screen uses (see ControlScheme), so a
# controller player sees controller buttons here rather than keyboard keys.

@export var player_controls_id : int = 1

# Movement deliberately has no row here: players already know how to move, and
# the cluster icon was the widest thing on the panel.
@onready var attack_sprite = $PanelContainer/MarginContainer/VBoxContainer/VBoxContainer2/Control/attack_controls
@onready var special_sprite = $PanelContainer/MarginContainer/VBoxContainer/VBoxContainer3/Control/special_controls

const P1_ACCENT_COLOR := Color(1.0, 1.0, 1.0) # white
const P2_ACCENT_COLOR := Color(0.79607844, 0.85882354, 0.9882353) # cbdbfc


func _ready() -> void:
	# The device is looked up here, at ready, rather than in a variable
	# initializer. Initializers run while the scene is still being built, and
	# GameManager.p1_device is null until a device has actually been claimed,
	# so dereferencing .display_name there crashed this node the moment a
	# real device was assigned - which is always the case with a controller
	# plugged in, since the pad claims the slot.
	var device := GameManager.p1_device if player_controls_id == 1 else GameManager.p2_device
	if device == null:
		push_warning("ControlsUI: no device claimed for player %d, leaving the panel empty" % player_controls_id)
		return

	_apply_control_changes(device, P1_ACCENT_COLOR if player_controls_id == 1 else P2_ACCENT_COLOR)


func _apply_control_changes(device: PlayerInputDevice, controls_color : Color) -> void:
	# Matched on the device, not on its display_name: a pad reports whatever
	# the OS calls it, so name matching missed every controller and left the
	# keyboard row showing instead.
	var scheme := ControlScheme.scheme_for(device)
	attack_sprite.frame = ControlScheme.normal_frame(scheme)
	special_sprite.frame = ControlScheme.special_frame(scheme)

	attack_sprite.modulate = controls_color
	special_sprite.modulate = controls_color
