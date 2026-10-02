extends Node

# ──────────────────────────────────────────────────────────────────
#  ComboManager (Autoload)
#
#  Tracks each player's combo: the number of hits they have landed on the
#  other player in a row, without being hit themselves, without a gap of
#  more than combo_window_seconds in between.
#
#  This is deliberately lenient. It used to be a strict link: the count was
#  reset the moment the victim returned to NEUTRAL, so only a true combo
#  (the victim never recovering) kept it alive. Now the victim recovering
#  does not break it - only landing a hit on the other player does, or
#  letting the window lapse.
#
#  The count is keyed by the player who is TAKING the hits, because that is
#  who the damage scaling in Player.take_hit() knows about: the count for a
#  defender is the combo their opponent is currently on.
#
#  Also turns the count into a damage-scaling multiplier so extended combos
#  do progressively less damage per hit (combo decay).

# Fired whenever a defender's combo count changes (new hit or reset to
# zero). defender_id is who is being combo'd, combo_count is their current
# hit total. UI listens to this to show a counter without polling.
signal combo_changed(defender_id: int, combo_count: int)

## How long a combo survives between hits, in seconds. Any hit landed inside
## the window extends it; once it lapses the count resets to zero.
@export var combo_window_seconds: float = 0.9
## Fraction of full damage removed for each hit past the first in a combo.
@export var combo_damage_reduction_per_hit: float = 0.1  # 10% less per extra hit
## Lowest the combo damage multiplier is allowed to go (never zero damage).
@export var combo_min_damage_scale: float = 0.5  # floor at 50% of full damage

var _combo_counts: Dictionary = {}  # defender_id -> current hit count
var _combo_timers: Dictionary = {}  # defender_id -> seconds left before it lapses


func _ready() -> void:
	EventBus.player_hit_landed.connect(_on_player_hit_landed)


func _process(delta: float) -> void:
	if _combo_timers.is_empty():
		return
	# keys() hands back a copy, so erasing inside the loop is safe.
	for defender_id in _combo_timers.keys():
		var remaining: float = _combo_timers[defender_id] - delta
		if remaining > 0.0:
			_combo_timers[defender_id] = remaining
			continue
		_reset_combo(defender_id)


func _on_player_hit_landed(attacker_id: int, _move_name: String, was_blocked: bool) -> void:
	# A blocked hit is not damage, so it neither extends the attacker's combo
	# nor breaks the defender's.
	if was_blocked:
		return
	var defender_id := _other_player_id(attacker_id)
	# The defender was just damaged, so their own streak is over: the counter
	# keyed by the attacker is the one carrying it.
	_reset_combo(attacker_id)
	_bump_combo(defender_id)


# Every landed hit refreshes the window, so a combo only ends when the
# attacker is hit or the hits stop coming.
func _bump_combo(defender_id: int) -> void:
	var new_count: int = _combo_counts.get(defender_id, 0) + 1
	_combo_counts[defender_id] = new_count
	_combo_timers[defender_id] = combo_window_seconds
	combo_changed.emit(defender_id, new_count)


func _reset_combo(defender_id: int) -> void:
	_combo_timers.erase(defender_id)
	if _combo_counts.get(defender_id, 0) == 0:
		return
	_combo_counts[defender_id] = 0
	combo_changed.emit(defender_id, 0)


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
