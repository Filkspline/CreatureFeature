extends Node

## Fallback effect used when a move has no hit_effect_scene of its own.
@export var default_hit_effect: PackedScene

## Fallback effect used when a move has no block_effect_scene of its own.
@export var default_block_effect: PackedScene


@export var debug: bool = true


func _ready() -> void:
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	_dbg("[SETUP] HitEffectManager ready, connected to EventBus.hit_confirmed. default_hit_effect=%s default_block_effect=%s" % [default_hit_effect, default_block_effect])


func _on_hit_confirmed(impact_position: Vector2, move_data: MoveData, _attacker: Node, _defender: Node, was_blocked: bool) -> void:
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
	effect.global_position = impact_position
	_dbg("[HIT CONFIRMED] spawned '%s' under '%s' at %s" % [scene.resource_path, parent.name, impact_position])
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


func _get_effects_parent() -> Node:
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.has_node("%EffectsLayer"):
		return current_scene.get_node("%EffectsLayer")
	return current_scene
