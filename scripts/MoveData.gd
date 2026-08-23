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

# ── Knockback / Launcher ─────────────────────────────────────────
# knock_back / block_knock_back are initial pushback SPEEDS (not a fixed
# distance) applied to the defender — they decelerate over time via the
# player's pushback_deceleration, same system pushback_on_block already
# uses. Actual travel distance is a function of this value AND that
# deceleration, so tune them together.
@export_group("Knockback")
@export var knock_back: float = 0.0        # defender's pushback speed on a HIT
@export var block_knock_back: float = 0.0  # defender's pushback speed on a BLOCKED hit

@export_group("Launcher")
@export var is_launcher: bool = false      # pops the opponent airborne on hit, forcing a knockdown on landing
@export var launcher_strength: float = 0.0 # upward launch speed if is_launcher is true (compare to jump_velocity)

@export_group("Advancing move")
@export var is_advancing: bool = false
@export var advance_speed: float = 0.0

@export_group("Special properties")
@export var low_profile: bool = false
@export var is_charge_move: bool = false
@export var charge_frames: int = 0
@export var fires_projectile: bool = false
@export var gatlings_into: Array[StringName] = []

@export_group("Projectile")
## Scene to instantiate when fire_projectile() is called from this move's
## animation. Only used if fires_projectile is true.
@export var projectile_scene: PackedScene
## Local offset from the spawning player's position. X is mirrored
## automatically to match the player's facing direction.
@export var projectile_spawn_offset: Vector2 = Vector2(40.0, -20.0)

@export_group("Upgrade state")
@export var upgrade_slot_id: StringName = ""
@export var is_upgraded: bool = false
@export var upgrade_property_id: StringName = ""
