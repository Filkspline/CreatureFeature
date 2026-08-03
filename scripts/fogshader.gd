extends ColorRect

@export var shader_material: ShaderMaterial

@export_category("Fog Settings")
@export var fog_color: Color = Color(0.8, 0.85, 0.9):
	set(value):
		fog_color = value
		update_shader_param("fog_color", value)

@export_range(0.0, 1.0, 0.01) var opacity: float = 0.25:
	set(value):
		opacity = value
		update_shader_param("opacity", value)

@export_range(0.0, 1.0, 0.01) var density: float = 0.5:
	set(value):
		density = value
		update_shader_param("density", value)

@export_range(1.0, 50.0, 0.5) var noise_scale: float = 8.0:
	set(value):
		noise_scale = value
		update_shader_param("noise_scale", value)

@export var scroll_speed: Vector2 = Vector2(0.02, 0.005):
	set(value):
		scroll_speed = value
		update_shader_param("scroll_speed", value)

@export_range(0.01, 1.0, 0.01) var softness: float = 0.4:
	set(value):
		softness = value
		update_shader_param("softness", value)

@export var full_screen: bool = true

func _ready():
	if full_screen:
		size = get_viewport_rect().size
		anchor_right = 1.0
		anchor_bottom = 1.0
		get_viewport().connect("size_changed", _on_viewport_resized)

	if not shader_material:
		shader_material = ShaderMaterial.new()
		shader_material.shader = preload("res://scripts/fog.gdshader")

	material = shader_material

	# Push current export values into the material now that it exists.
	update_shader_param("fog_color", fog_color)
	update_shader_param("opacity", opacity)
	update_shader_param("density", density)
	update_shader_param("noise_scale", noise_scale)
	update_shader_param("scroll_speed", scroll_speed)
	update_shader_param("softness", softness)

func _on_viewport_resized():
	size = get_viewport_rect().size

func update_shader_param(param_name: String, value):
	if shader_material:
		shader_material.set_shader_parameter(param_name, value)
