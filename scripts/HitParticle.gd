extends CPUParticles2D
const TEAR_SHADER := preload("res://scripts/impact_tear.gdshader")

# How small the effect starts before growing out to full size. 1.0 would
# mean no growth at all (old behavior — just a fade in place).
@export_range(0.0, 1.0, 0.01) var start_scale: float = 0.15
@export var grow_duration: float = 0.18

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
	color = Color(1.0, 0.949, 1.0, 0.902)
func _make_tear_effect() -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(200, 200)
	rect.position = -rect.size * 0.5
	rect.pivot_offset = rect.size * 0.5
	rect.scale = Vector2.ONE * start_scale
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = TEAR_SHADER
	mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0))
	mat.set_shader_parameter("rim_color", Color(1.0, 1.0, 1.0))
	rect.material = mat
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(rect, "scale", Vector2.ONE, grow_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(v): mat.set_shader_parameter("effect_alpha", v),
		1.0, 0.0, 0.18
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	return rect
