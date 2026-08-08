extends ParallaxBackground
# ── Camera ───────────────────────────────────────────────────────
@export var camera: Camera2D
# ── Scroll Speeds ────────────────────────────────────────────────
@export_group("Scroll Speeds")
@export_range(0.0, 1.0, 0.01) var sky_speed: float = 0.05:
	set(value):
		sky_speed = value
		_apply_speeds()
@export_range(0.0, 1.0, 0.01) var mountains_speed: float = 0.15:
	set(value):
		mountains_speed = value
		_apply_speeds()
@export_range(0.0, 1.0, 0.01) var buildingsflying_speed: float = 0.4:
	set(value):
		buildingsflying_speed = value
		_apply_speeds()
@export_range(0.0, 1.0, 0.01) var buildings_speed: float = 0.4:
	set(value):
		buildings_speed = value
		_apply_speeds()
@export_range(0.0, 1.0, 0.01) var platform_speed: float = 1.0:
	set(value):
		platform_speed = value
		_apply_speeds()

# ── Bobbing ──────────────────────────────────────────────────────
# Simple up/down wave that ripples from the front layer (Platform)
# back to the rearmost layer (Sky), each layer lagging the one in
# front of it by a fixed phase delay.
@export_group("Bobbing")
@export var bob_enabled: bool = true
@export_range(0.0, 50.0, 0.5) var bob_amplitude: float = 4.0  # pixels
@export_range(0.0, 3.0, 0.01) var bob_speed: float = 0.3       # cycles per second
@export_range(0.0, 3.14159, 0.01) var bob_phase_delay: float = 0.4  # radians between adjacent layers

var _bob_time: float = 0.0

@onready var _layers := {
	"Sky": $Sky,
	"Mountains": $Mountains,
	"BuildingsFlying": $BuildingsFlying,
	"Buildings": $Buildings,
	"Platform": $Platform,
}

# Ordered front → back so the wave ripples backward correctly.
const _BOB_ORDER := ["Buildings", "BuildingsFlying", "Mountains", "Sky"]

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_speeds()
	if not camera and not Engine.is_editor_hint():
		push_warning("[Parallax] no camera assigned in the Inspector — layers won't scroll.")

func _apply_speeds():
	if not is_inside_tree():
		return
	$Sky.motion_scale = Vector2(sky_speed, sky_speed)
	$Mountains.motion_scale = Vector2(mountains_speed, mountains_speed)
	$BuildingsFlying.motion_scale = Vector2(buildingsflying_speed, buildingsflying_speed)
	$Buildings.motion_scale = Vector2(buildings_speed, buildings_speed)
	$Platform.motion_scale = Vector2(platform_speed, platform_speed)

func _process(delta):
	if Engine.is_editor_hint():
		return
	if camera:
		scroll_offset = -camera.global_position
	if bob_enabled:
		_apply_bobbing(delta)

func _apply_bobbing(delta: float) -> void:
	_bob_time += delta
	var angular_speed := bob_speed * TAU
	for i in _BOB_ORDER.size():
		var layer_name: String = _BOB_ORDER[i]
		var layer: ParallaxLayer = _layers[layer_name]
		var phase := i * bob_phase_delay
		var y_offset := sin(_bob_time * angular_speed - phase) * bob_amplitude
		layer.motion_offset.y = y_offset
