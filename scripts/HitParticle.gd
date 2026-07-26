extends CPUParticles2D


func _ready() -> void:
	one_shot = true
	emitting = false
	_configure_particles()
	add_child(_Flash.new())


func play() -> void:
	emitting = true
	await finished
	queue_free()


func _configure_particles() -> void:
	amount = 24
	lifetime = 0.35
	explosiveness = 1.0
	randomness = 0.5
	direction = Vector2(0, -1)
	spread = 180.0
	gravity = Vector2(0, 260)
	initial_velocity_min = 140.0
	initial_velocity_max = 380.0
	angular_velocity_min = -720.0
	angular_velocity_max = 720.0
	scale_amount_min = 0.6
	scale_amount_max = 1.4
	hue_variation_min = -0.03
	hue_variation_max = 0.03

	texture = _make_spark_texture()

	# Shrink to nothing over the lifetime instead of just popping out —
	# reads as sparks fizzling rather than blinking off.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.7, 0.6))
	scale_curve.add_point(Vector2(1.0, 0.0))
	scale_amount_curve = scale_curve

	# Hot white core cooling through orange to red, fading at the tail.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.855, 0.91, 0.984, 0.706),
		Color(0.863, 0.898, 0.996, 0.733),
		Color(1.0, 0.15, 0.05, 0.0),
	])
	color_ramp = gradient


	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


# Soft radial dot, generated at runtime — no image asset required.
func _make_spark_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


class _Flash:
	extends Node2D

	var _radius: float = 3.0
	var _alpha: float = 1.0
	var _max_radius: float = 46.0
	var _duration: float = 0.18

	func _ready() -> void:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "_radius", _max_radius, _duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "_alpha", 0.0, _duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(queue_free)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var ring_col := Color(1.0, 1.0, 1.0, _alpha)
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, ring_col, 6.0, true)
		var core_radius: float = max(_max_radius - _radius, 0.0) * 0.3
		var core_col := Color(1, 1, 1, _alpha * 0.9)
		draw_circle(Vector2.ZERO, core_radius, core_col)
