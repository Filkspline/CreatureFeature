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
# NOTE: These tags are DATA-ONLY right now. testplayer1.gd does not yet
# apply them — it still uses pushback_on_block for everything. They exist
# so moves can be authored/tuned now without waiting on the knockback
# system. Setting any of these to a non-default value will print a
# runtime warning (see _warn_unimplemented_tags() in testplayer1.gd)
# so a "tuned" move doesn't silently do nothing once it's live.
@export_group("Knockback (not yet implemented)")
@export var knock_back: float = 0.0        # distance opponent is pushed on a HIT
@export var block_knock_back: float = 0.0  # distance opponent is pushed on a BLOCKED hit

@export_group("Launcher (not yet implemented)")
@export var is_launcher: bool = false      # does this move pop the opponent into the air on hit?
@export var launcher_strength: float = 0.0 # how high (launch velocity) if is_launcher is true

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
