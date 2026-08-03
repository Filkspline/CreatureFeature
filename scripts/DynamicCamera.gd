extends Camera2D

# ── Players ──────────────────────────────────────────────────────

@export_group("Players")
@export var player_1: Node2D
@export var player_2: Node2D

@export_group("Framing")
@export var player_padding := 50.0

@export_group("Shake")
@export var shake_decay: float = 20.0

var shake_amount: float = 0.0


func _ready():
	# Camera still works during hitstop
	process_mode = Node.PROCESS_MODE_ALWAYS

	EventBus.camera_shake.connect(_on_camera_shake)

	if not player_1 or not player_2:
		push_warning("[Camera] player_1 and/or player_2 not assigned in the Inspector — camera won't track anyone until both are set.")


func _get_tracked_players() -> Array:
	var tracked := []
	if player_1:
		tracked.append(player_1)
	if player_2:
		tracked.append(player_2)
	return tracked


func _on_camera_shake(amount: float):
	shake_amount = amount


func move():
	var tracked = _get_tracked_players()
	if tracked.is_empty():
		return

	var average_position := Vector2.ZERO
	for player in tracked:
		average_position += player.position
	average_position /= tracked.size()

	# Only follow horizontally (fighting game style)
	position.x = average_position.x


# Next two functions are so the player cant walk off screen
func get_left_boundary():
	return global_position.x - get_viewport_rect().size.x / (2 * zoom.x) + player_padding


func get_right_boundary():
	return global_position.x + get_viewport_rect().size.x / (2 * zoom.x) - player_padding


# Camera shake on hits
func apply_shake():
	if shake_amount > 0:
		offset = Vector2(
			randf_range(-shake_amount, shake_amount),
			randf_range(-shake_amount, shake_amount)
		)
	else:
		offset = Vector2.ZERO


func _process(delta):
	# Update player tracking
	move()

	# Apply camera shake
	apply_shake()

	# Fade shake out over time
	shake_amount = lerp(shake_amount, 0.0, delta * shake_decay)
