extends CharacterBody2D

@onready var hurtbox_shape: RectangleShape2D = $Area2D/hurtbox.shape
@onready var hitbox_shape: RectangleShape2D = $collision_box.shape
var base_hurtbox_size: Vector2
var base_hurtbox_position: Vector2

var opponent = null

var current_move: MoveData = null

var hit_connected: bool = false

var _hit_registered_this_activation: bool = false

var pushback_velocity_x: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	base_hurtbox_size = hurtbox_shape.size
	base_hurtbox_position = $Area2D/hurtbox.position
	
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player:
			opponent = p
			break
	if not opponent:
		push_warning("[SETUP] No opponent found in 'players' group.")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _check_hit() -> void:
	if not opponent:
		return

	var hitbox_area_shape = $Hitbox/MainHitbox
	if hitbox_area_shape.disabled:
		return

	var opponent_hurtbox = opponent.get_node("Hurtbox")
	for area in $Hitbox.get_overlapping_areas():
		if area == opponent_hurtbox or area.get_parent() == opponent_hurtbox:
			var was_blocked = opponent.take_hit(current_move, self)
			hit_connected = true
			_hit_registered_this_activation = true
			#EventBus.player_hit_landed.emit(player_id, current_move.move_name, was_blocked)
			EventBus.hit_confirmed.emit(hitbox_area_shape.global_position, current_move, self, opponent, was_blocked)
			
			#if hornet_selected == true:
			#	_dbg("[color=yellow][HORNET] Hornet activated")
			#	damage_dealt_bonus += _effect_hornet()
			
			EventBus.npc_cheer.emit() # Just here to call for the npc's to cheer when a player is hit
			
			if was_blocked:
				_apply_pushback()
			return

func _apply_pushback() -> void:
	if not current_move or not opponent:
		return
	pushback_velocity_x = _direction_away_from(opponent) * current_move.pushback_on_block
	
func _direction_away_from(other: Node2D) -> float:
	return -1.0 if other.global_position.x > global_position.x else 1.0
