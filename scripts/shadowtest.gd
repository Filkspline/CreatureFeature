# Shadow.gd
extends TextureRect
@export var player_id: int = 1
@export var ground_y: float = 0.0
@export var max_height: float = 200.0
@export var min_alpha: float = 0.2
@export var min_scale: float = 0.5

func _ready() -> void:
	if ground_y == 0.0:
		ground_y = global_position.y

func _process(_delta: float) -> void:
	
	pivot_offset = size / 2.0
	
	if not EventBus.player_position.has(player_id):
		return

	var pos: Vector2 = EventBus.player_position[player_id]
	global_position.x = pos.x - 65
	global_position.y = ground_y

	var is_airborne: bool = EventBus.player_is_airborne.get(player_id, false)
	if is_airborne:
		var height: float = ground_y - pos.y
		var t: float = clamp(height / max_height, 0.0, 1.0)
		modulate.a = lerp(1.0, min_alpha, t)
		scale = Vector2.ONE * lerp(1.0, min_scale, t)
	else:
		modulate.a = 1.0
		scale = Vector2.ONE
