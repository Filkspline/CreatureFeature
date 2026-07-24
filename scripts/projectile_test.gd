extends ColorRect

@export var shader_material: ShaderMaterial
@export var debug_mode: bool = false

@export_category("Movement")
@export var travel_speed: float = 60.0   # pixels per second
@export var move_horizontally: bool = true
@export var end_x: float = 2000.0
@export var loop: bool = true

@export_category("Look")
@export var ball_core_radius: float = 0.0:
	set(value):
		ball_core_radius = value
		update_shader_param("ball_core_radius", value)
@export var ball_glow_radius: float = 0.3:
	set(value):
		ball_glow_radius = value
		update_shader_param("ball_glow_radius", value)
@export var tear_strength: float = 0.09:
	set(value):
		tear_strength = value
		update_shader_param("tear_strength", value)
@export var tear_radius: float = 0.8:
	set(value):
		tear_radius = value
		update_shader_param("tear_radius", value)
@export var trail_length: float = 0.0:
	set(value):
		trail_length = value
		update_shader_param("trail_length", value)

@export_category("CRT Sync")
@export var crt_node_path: NodePath = NodePath("../ColorRect") # point this at your actual CRT node
@export var sync_crt_every_frame: bool = true # turn off if you want to save a few float reads and don't use hit_flash/screen_shake/super effects mid-flight

var start_x: float
var crt_node: Node = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_x = position.x  # use wherever the rect is placed in the editor

	print("--- ProjectileTest debug ---")
	print("Using editor-set position: ", position, " size: ", size)

	if debug_mode:
		color = Color.RED
		material = null
		return

	shader_material = ShaderMaterial.new()
	shader_material.shader = preload("res://scripts/energy_tear.gdshader")
	material = shader_material

	update_shader_param("rect_size", size)
	update_shader_param("ball_pos", Vector2(0.5, 0.5))
	update_shader_param("ball_core_radius", ball_core_radius)
	update_shader_param("ball_glow_radius", ball_glow_radius)
	update_shader_param("tear_strength", tear_strength)
	update_shader_param("tear_radius", tear_radius)
	update_shader_param("trail_length", trail_length)

	crt_node = get_node_or_null(crt_node_path)
	if crt_node:
		sync_crt_params()
	else:
		push_warning("ProjectileTest: couldn't find CRT node at path '%s'. Falling back to SUBTLE_RETRO defaults baked into the shader." % str(crt_node_path))

func _process(delta: float) -> void:
	if debug_mode:
		return

	if move_horizontally:
		position.x += travel_speed * delta
		if position.x > end_x:
			position.x = start_x if loop else end_x
			if not loop:
				set_process(false)

	if crt_node and sync_crt_every_frame:
		sync_crt_params()

func sync_crt_params() -> void:
	# Pull live values straight off the CRT node so this stays in sync
	# even mid-tween during add_hit_flash / add_screen_shake / activate_super_move_effects.
	update_shader_param("crt_curvature", crt_node.curvature)

	update_shader_param("crt_scanline_intensity", crt_node.scanline_intensity)
	update_shader_param("crt_scanline_count", crt_node.scanline_count)
	update_shader_param("crt_vignette_size", crt_node.vignette_size)
	update_shader_param("crt_brightness", crt_node.brightness)
	update_shader_param("crt_contrast", crt_node.contrast)
	update_shader_param("crt_saturation", crt_node.saturation)
	update_shader_param("crt_flicker", crt_node.flicker)
	update_shader_param("crt_noise_amount", crt_node.noise_amount)

func update_shader_param(param_name: String, value) -> void:
	if shader_material:
		shader_material.set_shader_parameter(param_name, value)
