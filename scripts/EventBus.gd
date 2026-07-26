extends Node
# Signals for communication between nodes
signal player_state_changed(new_state: int)
signal player_health_changed(new_health: float)
signal player_attack_started(move_name: String)
signal player_hit_landed(move_name: String, was_blocked: bool)

# Fired the instant a hitbox/hurtbox overlap is confirmed in _check_hit().

signal hit_confirmed(impact_position: Vector2, move_data: MoveData, attacker: Node, defender: Node, was_blocked: bool)

# Data that opponents/UI can read every frame
var player_position: Vector2
var player_velocity: Vector2
var player_is_airborne: bool
var player_state: int
var player_crouching: bool
var player_blocking_low: bool
