extends CPUParticles2D
# Attached directly to the root CPUParticles2D node — this node IS the
# particle emitter. The flashy part of the effect is now the shared
# impact_tear shader (res://shaders/impact_tear.gdshader) instead of a
# hand-drawn _Flash class, so this script only configures a small burst
# of sparks and spawns one ColorRect running that shader on top.
#
# Does NOT auto-emit on _ready(). add_child() calls _ready() synchronously,
# before the caller (HitEffectManager) gets a chance to set global_position
# — so starting emission here would fire the whole one-shot burst at the
# node's default (0, 0) position every time, regardless of where it was
# spawned. Call play() explicitly once the node's position is set instead.

const TEAR_SHADER := preload("res://scripts/impact_tear.gdshader")


func _ready() -> void:
	one_shot = true
	emitting = false
	_configure_particles()
	add_child(_make_tear_effect())


func play() -> void:
	emitting = true
	await finished
	queue_free()


func _configure_particles() -> void:
	amount = 16
	lifetime = 0.15
	explosiveness = 1.0
	randomness = 0.5
	direction = Vector2(0, -1)
	spread = 180.0
	gravity = Vector2(0, 260)
	initial_velocity_min = 100.0
	initial_velocity_max = 260.0
	scale_amount_min = 0.5
	scale_amount_max = 1.0
	color = Color(0.9, 0.95, 1.0, 0.9)


func _make_tear_effect() -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(200, 200)
	rect.position = -rect.size * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = TEAR_SHADER
	mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0))
	mat.set_shader_parameter("rim_color", Color(1.0, 1.0, 1.0))
	rect.material = mat

	var tween := create_tween()
	tween.tween_method(
		func(v): mat.set_shader_parameter("effect_alpha", v),
		1.0, 0.0, 0.18
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	return rect
