extends Resource
class_name UpgradeData

#  UpgradeData

#  Adding a brand new stat upgrade (e.g. crouch speed) needs zero
#  code changes: just make a new .tres, set effect_type to STAT_BOOST,
#  and set stat_name to whatever key Player's stats dict uses.

enum EffectType {
	STAT_BOOST,   # flat/percent change to an existing player stat
	MULTI_STAT_BOOST,
	UNLOCK_MOVE,  # grants access to a move that wasn't usable before
	MOVE_MODIFY,  # tweaks a property on an existing move
}

@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D

@export var effect_type: EffectType = EffectType.STAT_BOOST

# ── Stat boost ──
# stat_name should match a key in Player's stats dict (e.g. "max_health",
# "move_speed", "jump_velocity"). is_percent lets the same fields cover
# both "+10 max hp" and "+15% move speed" without extra vars.
@export_group("Stat boost")
@export var stat_name: StringName = ""
@export var stat_amount: float = 0.0
@export var is_percent: bool = false

# ── Multi stat boost ──
# stat_name should match a key in Player's stats dict (e.g. "max_health",
# "move_speed", "jump_velocity"). is_percent lets the same fields cover
# both "+10 max hp" and "+15% move speed" without extra vars.
@export_group("Multi stat boost")
@export var stat_names_array: Array[String] = []
@export var stat_amounts_array: Array[float] = []
@export var is_percents_array: Array[bool] = []

# ── Unlock move ──
# Points straight at the MoveData that becomes available.
@export_group("Unlock move")
@export var unlocked_move: MoveData

# ── Move modify ──
# target_upgrade_slot_id matches MoveData.upgrade_slot_id, so this
# targets a move's role (e.g. "launcher") rather than its exact name.
@export_group("Move modify")
@export var target_upgrade_slot_id: StringName = ""
@export var move_property: StringName = ""
@export var move_delta: float = 0.0


## Applies this upgrade to the given player. Player owns the actual
## mutation logic this just tells it what kind of change to make.
func apply_to(player) -> void:
	match effect_type:
		EffectType.STAT_BOOST:
			player.apply_stat_boost(stat_name, stat_amount, is_percent)
		EffectType.MULTI_STAT_BOOST:
			player.apply_multi_stat_boost(stat_names_array, stat_amounts_array, is_percents_array)
		EffectType.UNLOCK_MOVE:
			player.unlock_move(unlocked_move)
		EffectType.MOVE_MODIFY:
			player.modify_move(target_upgrade_slot_id, move_property, move_delta)
