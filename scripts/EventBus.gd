extends Node

# ── Per-instance events — player_id identifies which Player fired it ──
signal player_state_changed(player_id: int, new_state: int)
signal player_health_changed(player_id: int, new_health: float)
signal player_attack_started(player_id: int, move_name: String)
signal player_hit_landed(player_id: int, move_name: String, was_blocked: bool)

# Not player-specific
signal camera_shake(amount: float)

# Already carries attacker/defender node refs directly — no id needed
signal hit_confirmed(impact_position: Vector2, move_data: MoveData, attacker: Node, defender: Node, was_blocked: bool)

# ── Continuous per-frame state, keyed by player_id ──
var player_position: Dictionary = {}     # int -> Vector2
var player_velocity: Dictionary = {}     # int -> Vector2
var player_is_airborne: Dictionary = {}  # int -> bool
var player_state: Dictionary = {}        # int -> int
var player_crouching: Dictionary = {}    # int -> bool
var player_blocking_low: Dictionary = {} # int -> bool
