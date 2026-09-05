extends Node

# ──────────────────────────────────────────────────────────────────
#  ComboManager (Autoload)
#
#  Tracks each defender's current combo hit count and turns it into a
#  damage-scaling multiplier so extended combos do progressively less
#  damage per hit (combo decay). Listens to existing EventBus signals
#  only: player_hit_landed bumps the count, player_state_changed resets
#  it once the defender returns to NEUTRAL.

# Fired whenever a defender's combo count changes (new hit or reset to
# zero). defender_id is who is being combo'd, combo_count is their current
# hit total. UI listens to this to show a counter without polling.
signal combo_changed(defender_id: int, combo_count: int)

## Fraction of full damage removed for each hit past the first in a combo.
@export var combo_damage_reduction_per_hit: float = 0.1  # 10% less per extra hit
## Lowest the combo damage multiplier is allowed to go (never zero damage).
@export var combo_min_damage_scale: float = 0.2  # floor at 20% of full damage

var _combo_counts: Dictionary = {}  # defender_id -> current hit count


func _ready() -> void:
	EventBus.player_hit_landed.connect(_on_player_hit_landed)
	EventBus.player_state_changed.connect(_on_player_state_changed)


func _on_player_hit_landed(attacker_id: int, _move_name: String, was_blocked: bool) -> void:
	# Blocked hits don't keep a combo going (the defender never left neutral).
	if was_blocked:
		return
	var defender_id := _other_player_id(attacker_id)
	var new_count: int = _combo_counts.get(defender_id, 0) + 1
	_combo_counts[defender_id] = new_count
	combo_changed.emit(defender_id, new_count)


func _on_player_state_changed(player_id: int, new_state: int) -> void:
	# State.NEUTRAL is 0. A defender back in neutral is no longer being
	# combo'd, so their counter drops to zero.
	if new_state != 0:
		return
	if _combo_counts.get(player_id, 0) == 0:
		return
	_combo_counts[player_id] = 0
	combo_changed.emit(player_id, 0)


func get_combo_count(defender_id: int) -> int:
	return _combo_counts.get(defender_id, 0)


## Damage multiplier for a defender currently being combo'd. The first hit
## is full damage (1.0); each subsequent hit is reduced by
## combo_damage_reduction_per_hit and clamped to combo_min_damage_scale.
func get_combo_damage_scale(defender_id: int) -> float:
	var count := get_combo_count(defender_id)
	if count <= 1:
		return 1.0
	var scale: float = 1.0 - (count - 1) * combo_damage_reduction_per_hit
	return max(scale, combo_min_damage_scale)


func _other_player_id(player_id: int) -> int:
	return 2 if player_id == 1 else 1
