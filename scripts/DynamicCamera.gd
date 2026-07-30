extends Camera2D

var players = []
@export var player_padding := 50.0
# Screen shake variables
var shake_amount: float = 0.0
var shake_decay: float = 20.0


func _ready():
	# Camera still works during hitstop
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find all current fighters
	players = get_tree().get_nodes_in_group("players")
	
	# Listen for hit shake events
	EventBus.camera_shake.connect(_on_camera_shake)


func _on_camera_shake(amount: float):
	shake_amount = amount


func move():
	if players.size() == 0:
		return

	var average_position := Vector2.ZERO

	for player in players:
		average_position += player.position

	average_position /= players.size()

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
