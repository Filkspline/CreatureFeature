extends Control

@export var player_controls_id : int = 1

@onready var movement_sprite = $PanelContainer/MarginContainer/VBoxContainer/VBoxContainer/Control/movement_controls
@onready var attack_sprite = $PanelContainer/MarginContainer/VBoxContainer/VBoxContainer2/Control/attack_controls
@onready var special_sprite = $PanelContainer/MarginContainer/VBoxContainer/VBoxContainer3/Control/special_controls

const P1_ACCENT_COLOR := Color(1.0, 1.0, 1.0) # white
const P2_ACCENT_COLOR := Color(0.79607844, 0.85882354, 0.9882353) # cbdbfc

var p1_device = GameManager.p1_device.display_name
var p2_device = GameManager.p2_device.display_name

# First number in the array is the icon for movement, second is icon for attack,
# third is icon for special
var sprite_sheet_frame_map = {"Keyboard (WASD)": [0, 5, 6], "Keyboard (Arrows)": [7, 12, 13], "Xbox One Controller": [15, 18, 19]}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	match player_controls_id:
		GameManager.p1_character_id:
			_apply_control_changes(p1_device, P1_ACCENT_COLOR)
		GameManager.p2_character_id:
			_apply_control_changes(p2_device, P2_ACCENT_COLOR)

func _apply_control_changes(device_name : String, controls_color : Color) -> void:
	var sprite_map_array = sprite_sheet_frame_map.get(device_name)
	movement_sprite.frame = sprite_map_array[0]
	attack_sprite.frame = sprite_map_array[1]
	special_sprite.frame = sprite_map_array[2]
	
	movement_sprite.modulate = controls_color
	attack_sprite.modulate = controls_color
	special_sprite.modulate = controls_color
