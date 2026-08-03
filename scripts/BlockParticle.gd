extends CPUParticles2D


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
	amount = 10
	lifetime = 0.2
	explosiveness = 1.0
	randomness = 0.4
	direction = Vector2(0, -1)
	spread = 100.0
	gravity = Vector2(0, 120)
	initial_velocity_min = 60.0
	initial_velocity_max = 160.0
	scale_amount_min = 0.4
	scale_amount_max = 0.8
	color = Color(0.55, 0.75, 1.0, 0.85)


func _make_tear_effect() -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(160, 160)
	rect.position = -rect.size * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = TEAR_SHADER
	mat.set_shader_parameter("core_color", Color(0.6, 0.85, 1.0))
	mat.set_shader_parameter("rim_color", Color(0.2, 0.5, 1.0))
	mat.set_shader_parameter("tear_strength", 0.01)
	mat.set_shader_parameter("chrom_strength", 0.006)
	rect.material = mat

	var tween := create_tween()
	tween.tween_method(
		func(v): mat.set_shader_parameter("effect_alpha", v),
		1.0, 0.0, 0.22
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	return rect
