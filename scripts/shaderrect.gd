extends ColorRect

@export var shader_material: ShaderMaterial

# Effect parameters
@export_category("CRT Settings")
@export var curvature: float = 0.03:
	set(value):
		curvature = value
		update_shader_param("curvature", value)

@export var scanline_intensity: float = 0.08:
	set(value):
		scanline_intensity = value
		update_shader_param("scanline_intensity", value)

@export var scanline_count: float = 600:
	set(value):
		scanline_count = value
		update_shader_param("scanline_count", value)

@export var vignette_size: float = 0.15:
	set(value):
		vignette_size = value
		update_shader_param("vignette_size", value)

@export var brightness: float = 1.05:
	set(value):
		brightness = value
		update_shader_param("brightness", value)

@export var contrast: float = 1.03:
	set(value):
		contrast = value
		update_shader_param("contrast", value)

@export var saturation: float = 1.05:
	set(value):
		saturation = value
		update_shader_param("saturation", value)

@export_category("RGB Effects")
@export var chromatic_aberration: float = 0.001:
	set(value):
		chromatic_aberration = value
		update_shader_param("chromatic_aberration", value)

@export var rgb_shift: Vector3 = Vector3.ZERO:
	set(value):
		rgb_shift = value
		update_shader_param("rgb_shift", value)

@export_category("Glow Effects")
@export var glow_size: float = 0.001:
	set(value):
		glow_size = value
		update_shader_param("glow_size", value)

@export var glow_intensity: float = 0.08:
	set(value):
		glow_intensity = value
		update_shader_param("glow_intensity", value)

@export_category("Screen Effects")
@export var distortion: float = 0.003:
	set(value):
		distortion = value
		update_shader_param("distortion", value)

@export var flicker: float = 0.002:
	set(value):
		flicker = value
		update_shader_param("flicker", value)

@export var noise_amount: float = 0.004:
	set(value):
		noise_amount = value
		update_shader_param("noise_amount", value)

# Presets
@export_category("Presets")
enum Presets {CUSTOM, SUBTLE_RETRO, VERY_LIGHT, ARCADE_LIGHT, FIGHTING_GAME}
@export var current_preset: Presets = Presets.FIGHTING_GAME:
	set(value):
		current_preset = value
		apply_preset(value)

# Layer this gets moved into. Higher than the implicit base layer (0) that
# everything outside a CanvasLayer draws on — including your gameplay world
# and the hit/block particle effects — so this always draws last, on top,
# with a clean SCREEN_TEXTURE snapshot of everything below it.
const CRT_LAYER := 10


func _ready():
	# Make sure the ColorRect covers the entire screen
	size = get_viewport_rect().size
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Create or assign shader material
	if not shader_material:
		shader_material = ShaderMaterial.new()
		shader_material.shader = preload("res://scripts/testshader.gdshader")

	material = shader_material

	# Apply default preset
	apply_preset(current_preset)

	# Connect to viewport resize
	get_viewport().connect("size_changed", _on_viewport_resized)

	# Move into a dedicated CanvasLayer. As a plain node in the 2D world
	# tree, this rect's "full screen" coverage was computed once in WORLD
	# space and never updated — so as soon as Camera2D panned horizontally
	# to track the players, this rect drifted out of alignment with what
	# was actually on screen. It also meant this rect and the particle
	# effects (both large opaque SCREEN_TEXTURE-sampling quads) were
	# competing for z_index-based draw order in the same canvas layer,
	# which is why particles were disappearing under it. A CanvasLayer is
	# screen-space by definition, so it always matches the viewport
	# regardless of camera position, and always draws after the base
	# layer's content — sidestepping both problems at once.
	# Deferred because reparenting during our own _ready() (while the
	# scene is still finishing instantiating siblings) can otherwise hit
	# "parent node is busy" errors.
	call_deferred("_move_to_canvas_layer")


func _move_to_canvas_layer() -> void:
	if get_parent() is CanvasLayer:
		return  # already moved — avoids double-wrapping on scene reload

	var old_parent := get_parent()
	var layer := CanvasLayer.new()
	layer.layer = CRT_LAYER
	old_parent.add_child(layer)

	reparent(layer, false)

	# Re-apply full-screen coverage now that we're in screen space —
	# belt-and-braces in case reparent() nudged anything.
	size = get_viewport_rect().size
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _on_viewport_resized():
	size = get_viewport_rect().size

func update_shader_param(param_name: String, value):
	if shader_material:
		shader_material.set_shader_parameter(param_name, value)

func apply_preset(preset: Presets):
	match preset:
		Presets.SUBTLE_RETRO:
			curvature = 0.04
			scanline_intensity = 0.12
			scanline_count = 500
			vignette_size = 0.2
			brightness = 1.08
			contrast = 1.05
			saturation = 1.08
			chromatic_aberration = 0.0015
			rgb_shift = Vector3.ZERO
			glow_size = 0.0015
			glow_intensity = 0.1
			distortion = 0.0004
			flicker = 0.003
			noise_amount = 0.005

		Presets.VERY_LIGHT:
			curvature = 0.02
			scanline_intensity = 0.05
			scanline_count = 700
			vignette_size = 0.1
			brightness = 1.03
			contrast = 1.02
			saturation = 1.03
			chromatic_aberration = 0.0005
			rgb_shift = Vector3.ZERO
			glow_size = 0.0008
			glow_intensity = 0.05
			distortion = 0.002
			flicker = 0.001
			noise_amount = 0.002

		Presets.ARCADE_LIGHT:
			curvature = 0.05
			scanline_intensity = 0.15
			scanline_count = 450
			vignette_size = 0.25
			brightness = 1.1
			contrast = 1.08
			saturation = 1.1
			chromatic_aberration = 0.002
			rgb_shift = Vector3(0.0005, 0.0, -0.0005)
			glow_size = 0.002
			glow_intensity = 0.15
			distortion = 0.005
			flicker = 0.004
			noise_amount = 0.006

		Presets.FIGHTING_GAME:
			# Super subtle - barely noticeable but adds atmosphere
			curvature = 0.025
			scanline_intensity = 0.06
			scanline_count = 650
			vignette_size = 0.12
			brightness = 1.04
			contrast = 1.03
			saturation = 1.04
			chromatic_aberration = 0.0008
			rgb_shift = Vector3(0.0003, 0.0, -0.0003)
			glow_size = 0.001
			glow_intensity = 0.06
			distortion = 0.002
			flicker = 0.0015
			noise_amount = 0.003

# Optional: Super subtle hit effect
func add_hit_flash(duration: float = 0.08):
	var original_brightness = brightness
	var tween = create_tween()
	tween.tween_method(func(value):
		update_shader_param("brightness", value), brightness, brightness * 1.15, duration / 2)
	tween.tween_method(func(value):
		update_shader_param("brightness", value), brightness * 1.15, original_brightness, duration / 2)

# Optional: Subtle screen shake effect
func add_screen_shake(intensity: float = 0.008, duration: float = 0.15):
	var original_distortion = distortion
	var tween = create_tween()
	tween.tween_method(func(value):
		update_shader_param("distortion", value), distortion, distortion + intensity, duration / 2)
	tween.tween_method(func(value):
		update_shader_param("distortion", value), distortion + intensity, original_distortion, duration / 2)

# Optional: Intensify effects during super moves
func activate_super_move_effects(duration: float = 2.0):
	# Store original values
	var orig_chromatic = chromatic_aberration
	var orig_glow = glow_intensity
	var orig_distortion = distortion

	# Ramp up effects
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_method(func(value):
		update_shader_param("chromatic_aberration", value), chromatic_aberration, 0.003, 0.3)
	tween.tween_method(func(value):
		update_shader_param("glow_intensity", value), glow_intensity, 0.2, 0.3)
	tween.tween_method(func(value):
		update_shader_param("distortion", value), distortion, 0.01, 0.3)

	# Return to normal after duration
	await get_tree().create_timer(duration).timeout

	var return_tween = create_tween()
	return_tween.set_parallel(true)
	return_tween.tween_method(func(value):
		update_shader_param("chromatic_aberration", value), 0.003, orig_chromatic, 0.5)
	return_tween.tween_method(func(value):
		update_shader_param("glow_intensity", value), 0.2, orig_glow, 0.5)
	return_tween.tween_method(func(value):
		update_shader_param("distortion", value), 0.01, orig_distortion, 0.5)
