@tool
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
@export_range(0.0, 1.0, 0.01) var buildings_speed: float = 0.4:
	set(value):
		buildings_speed = value
		_apply_speeds()
@export_range(0.0, 1.0, 0.01) var platform_speed: float = 1.0:
	set(value):
		platform_speed = value
		_apply_speeds()

@onready var _layers := {
	"Sky": $Sky,
	"Mountains": $Mountains,
	"Buildings": $Buildings,
	"Platform": $Platform,
}

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
	$Buildings.motion_scale = Vector2(buildings_speed, buildings_speed)
	$Platform.motion_scale = Vector2(platform_speed, platform_speed)

func _process(_delta):
	if Engine.is_editor_hint():
		return
	if camera:
		scroll_offset = -camera.global_position
