extends Node2D

const TEAR_SHADER := preload("res://scripts/impact_tear.gdshader")

# How small the screen-tear overlay starts before growing to full size.
@export_range(0.0, 1.0, 0.01) var start_scale: float = 0.15
@export var grow_duration: float = 0.18

# Hit spark flip-book. Sprite2D child is authored facing left-to-right;
# flip_h handles hits going the other way.
@export var frame_count: int = 6
@export var frame_duration: float = 0.04
@export var random_rotation_max_degrees: float = 55.0

## Hit direction, set externally by HitEffectManager before play() is
## called. Positive x = attacker on the left (hit travels left to right,
## sprite plays unflipped). Negative x flips it.
var direction: Vector2 = Vector2.RIGHT

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	# hframes/vframes are NOT set here on purpose — they're configured
	# directly on the Sprite2D child in the editor to match whatever grid
	# your actual spritesheet uses. Overwriting them from script here was
	# the cause of the sprite showing cropped wrong: it forced a
	# single-row 6-column slice regardless of how the real image is
	# actually laid out. frame_count below should just match however many
	# frames you've got the Sprite2D grid-sliced into in the editor.
	sprite.frame = 0
	rotation = deg_to_rad(randf_range(-random_rotation_max_degrees, random_rotation_max_degrees))
	_insert_tear_effect_behind_self()


func play() -> void:
	sprite.flip_h = direction.x < 0.0

	for i in frame_count:
		sprite.frame = i
		# ignore_time_scale so the spark still reads clearly even during
		# hitstop, same reasoning GameManager already uses for its own
		# hitstop timer: this is exactly the moment hitstop freezes
		# everything else, so the impact frame needs to keep animating
		# through it rather than freezing on frame 0 for the whole freeze.
		await get_tree().create_timer(frame_duration, true, false, true).timeout

	queue_free()


# Adds the tear/glow overlay as a SIBLING of this node (in the same
# parent), positioned directly before it in the child list, so normal
# draw order puts it underneath the sprite. Deliberately avoids z_index:
# z_index sorts globally across the whole canvas layer, not just within
# this node's own subtree, so using it here previously shifted draw order
# for unrelated screen-texture shaders elsewhere in the game (the CRT
# shader, the original full-screen tear effect), since they sample
# "whatever's drawn so far" and this node's position in that order
# mattered to them even though they have nothing to do with this hit
# effect. Sibling ordering only affects this burst's own two pieces
# relative to each other.
func _insert_tear_effect_behind_self() -> void:
	var rect := _make_tear_effect()
	var parent := get_parent()
	if not parent:
		add_child(rect)
		return
	parent.add_child(rect)
	rect.global_position = global_position
	parent.move_child(rect, get_index())


func _make_tear_effect() -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(200, 200)
	rect.position = -rect.size * 0.5
	rect.pivot_offset = rect.size * 0.5
	rect.scale = Vector2.ONE * start_scale
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = TEAR_SHADER
	# Keep the tear overlay dark too, so the whole hit effect reads as
	# black/dark with no other colors.
	mat.set_shader_parameter("core_color", Color(0.02, 0.02, 0.02, 1.0))
	mat.set_shader_parameter("rim_color", Color(0.02, 0.02, 0.02, 1.0))
	rect.material = mat
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(rect, "scale", Vector2.ONE, grow_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(v): mat.set_shader_parameter("effect_alpha", v),
		1.0, 0.0, 0.18
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# Not parented to `self` anymore, so it won't get freed automatically
	# when this node does at the end of play(). Free it on the same
	# timeline as the tween driving its own fade.
	tween.chain().tween_callback(rect.queue_free)
	return rect
