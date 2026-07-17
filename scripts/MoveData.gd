# MoveData.gd
extends Resource
class_name MoveData

enum HitLevel { LOW, MID, OVERHEAD }
enum InputDir { NEUTRAL, FORWARD, BACK, DOWN, UP }
enum Kind { NORMAL, SPECIAL, GRAB }

@export var move_name: String = ""
@export var input_dir: InputDir
@export var kind: Kind
@export var hit_level: HitLevel

@export_group("Frame data")
@export var startup: int = 5
@export var active: int = 3
@export var recovery: int = 10
@export var block_advantage: int = -2
@export var hitstun: int = 12
@export var damage: float = 0.0

@export_group("Animation")
@export var animation_name: StringName = ""

@export_group("Pushback")
@export var pushback_on_block: float = 200.0

@export_group("Advancing move")
@export var is_advancing: bool = false
@export var advance_speed: float = 0.0

@export_group("Special properties")
@export var low_profile: bool = false
@export var is_charge_move: bool = false
@export var charge_frames: int = 0
@export var fires_projectile: bool = false
@export var gatlings_into: Array[StringName] = []

@export_group("Upgrade state")
@export var upgrade_slot_id: StringName = ""
@export var is_upgraded: bool = false
@export var upgrade_property_id: StringName = ""
