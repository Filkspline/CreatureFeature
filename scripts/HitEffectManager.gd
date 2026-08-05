extends Node
# Autoload singleton. Listens for EventBus.hit_confirmed and spawns the
# appropriate particle effect at the impact point. Add as an autoload
# via the HitEffectManager.tscn wrapper (not this script directly) so the
# default effect scenes can be assigned in the Inspector.

## Fallback effect used when a move has no hit_effect_scene of its own.
@export var default_hit_effect: PackedScene

## Fallback effect used when a move has no block_effect_scene of its own.
@export var default_block_effect: PackedScene

## Temporary — prints each step of the pipeline so you can see exactly
## where a hit effect is (or isn't) making it through. Turn off once
## particles are confirmed working.
@export var debug: bool = true


## How much impact_position.x nudges the spawn x away from the defender's
## own x. 0.0 = spawns exactly on the defender's x; 1.0 = spawns exactly on
## the impact x. Kept low so it reads as "on the defender" with a slight
## pull toward where the hit actually landed.
@export_range(0.0, 1.0, 0.01) var impact_x_influence: float = 0.25
@export_range(0.0, 1.0, 0.01) var impact_y_influence: float = 0.85



func _ready() -> void:
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	_dbg("[SETUP] HitEffectManager ready, connected to EventBus.hit_confirmed. default_hit_effect=%s default_block_effect=%s" % [default_hit_effect, default_block_effect])


func _on_hit_confirmed(impact_position: Vector2, move_data: MoveData, _attacker: Node, defender: Node, was_blocked: bool) -> void:
	_dbg("[HIT CONFIRMED] received signal | pos=%s move=%s blocked=%s" % [impact_position, move_data.move_name if move_data else "null", was_blocked])

	var scene := _pick_effect(move_data, was_blocked)
	if not scene:
		_dbg("[HIT CONFIRMED] no effect scene resolved (defaults unassigned?) -> aborting")
		return

	var parent := _get_effects_parent()
	if not parent:
		_dbg("[HIT CONFIRMED] no valid parent from _get_effects_parent() (current_scene is null?) -> aborting")
		return

	var effect := scene.instantiate()
	parent.add_child(effect)
	var spawn_x: float = lerp((defender as Node2D).global_position.x, impact_position.x, impact_x_influence)
	var spawn_y: float = lerp((defender as Node2D).global_position.y, impact_position.y, impact_y_influence)
	var spawn_position := Vector2(spawn_x, spawn_y)
	effect.global_position = spawn_position
	_dbg("[HIT CONFIRMED] spawned '%s' under '%s' at %s" % [scene.resource_path, parent.name, spawn_position])
	effect.play()


func _dbg(msg: String) -> void:
	if debug:
		print(msg)


func _pick_effect(move_data: MoveData, was_blocked: bool) -> PackedScene:
	if was_blocked:
		if move_data and "block_effect_scene" in move_data and move_data.block_effect_scene:
			return move_data.block_effect_scene
		return default_block_effect

	if move_data and "hit_effect_scene" in move_data and move_data.hit_effect_scene:
		return move_data.hit_effect_scene
	return default_hit_effect


# Prefer a scene-unique "%EffectsLayer" node in the current scene if one
# exists (keeps effects from fighting gameplay nodes for z-index/parenting
# as more layers get added later). Falls back to current_scene directly.
func _get_effects_parent() -> Node:
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.has_node("%EffectsLayer"):
		return current_scene.get_node("%EffectsLayer")
	return current_scene
