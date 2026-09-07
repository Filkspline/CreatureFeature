extends CPUParticles2D
const TEAR_SHADER := preload("res://scripts/impact_tear.gdshader")

# How small the screen-tear overlay starts before growing to full size.
@export_range(0.0, 1.0, 0.01) var start_scale: float = 0.15
@export var grow_duration: float = 0.18

# Hit spark particle tunables. Defaults are a quick, punchy, near-black
# burst so the look can be adjusted in the Inspector without touching code.
@export var particle_count: int = 24
@export var particle_lifetime: float = 0.15
@export var particle_spread: float = 180.0
@export var particle_gravity: Vector2 = Vector2(0, 260)
@export var particle_velocity_min: float = 100.0
@export var particle_velocity_max: float = 260.0
@export var particle_color: Color = Color(0.02, 0.02, 0.02, 1.0)  # near-black spark


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
	amount = particle_count
	lifetime = particle_lifetime
	explosiveness = 1.0
	randomness = 0.5
	direction = Vector2(0, -1)  # default; HitEffectManager overrides per hit
	spread = particle_spread
	gravity = particle_gravity
	initial_velocity_min = particle_velocity_min
	initial_velocity_max = particle_velocity_max
	scale_amount_min = 0.5
	scale_amount_max = 1.0
	color = particle_color


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
	return rect
