# Shadow.gd
extends TextureRect


@export var ground_y: float = 0.0

# How far up (in pixels) counts as "fully airborne" for scale/fade purposes.
@export var max_height: float = 200.0

@export var min_alpha: float = 0.2
@export var min_scale: float = 0.5

func _ready() -> void:
	if ground_y == 0.0:
		ground_y = global_position.y

func _process(_delta: float) -> void:
	global_position.x = EventBus.player_position.x - 65
	global_position.y = ground_y

	if EventBus.player_is_airborne:
		var height: float = ground_y - EventBus.player_position.y
		var t: float = clamp(height / max_height, 0.0, 1.0)
		modulate.a = lerp(1.0, min_alpha, t)
		scale = Vector2.ONE * lerp(1.0, min_scale, t)
	else:
		modulate.a = 1.0
		scale = Vector2.ONE
