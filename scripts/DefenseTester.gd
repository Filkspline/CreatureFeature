extends CharacterBody2D
class_name DefenseTester

# ── Visuals ──────────────────────────────────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var hurtbox_collision: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var state_label: Label = $Label if has_node("Label") else null

var base_color: Color = Color.WHITE
var state_color: Color = Color.WHITE
var flash_color: Color = Color.RED
var is_flashing: bool = false
var flash_timer: float = 0.0
const FLASH_DURATION: float = 0.15

# ── States ──────────────────────────────────────────────────────
enum State {
	IDLE,
	CROUCHING,
	JUMPING,
	BLOCKING_STAND,
	BLOCKING_CROUCH,
	HITSTUN,
	BLOCKSTUN
}

# ── Inspector – which behaviours are allowed ───────────────────
@export_group("Allowed Behaviours")
@export var can_idle: bool = true
@export var can_crouch: bool = true
@export var can_jump: bool = true
@export var can_block_stand: bool = true
@export var can_block_crouch: bool = true

# ── Duration ranges (seconds) ──────────────────────────────────
@export_group("State Durations")
@export var idle_min: float = 0.8
@export var idle_max: float = 2.0
@export var crouch_min: float = 0.5
@export var crouch_max: float = 1.5
@export var block_stand_min: float = 0.6
@export var block_stand_max: float = 1.8
@export var block_crouch_min: float = 0.6
@export var block_crouch_max: float = 1.8

# ── Test mode ──────────────────────────────────────────────────
@export_group("Test Mode")
@export var always_block: bool = false

# ── Internal state ────────────────────────────────────────────
var current_state: State = State.IDLE
var state_timer: float = 0.0
var state_duration: float = 0.0
var stun_timer: float = 0.0

# ── Movement ────────────────────────────────────────────────────
const GRAVITY: float = 980.0
const JUMP_VELOCITY: float = -400.0

# ── Hurtbox dimensions ──────────────────────────────────────────
var base_hurtbox_size: Vector2 = Vector2(80, 160)
var base_hurtbox_position: Vector2 = Vector2(0, -80)
var crouch_size: Vector2 = Vector2(80, 110)
var crouch_position: Vector2 = Vector2(0, -55)
var jump_size: Vector2 = Vector2(80, 120)
var jump_position: Vector2 = Vector2(0, -100)


func _ready() -> void:
	add_to_group("players")
	if not always_block:
		_change_state(State.IDLE)
	else:
		_change_state(State.BLOCKING_STAND)
	_update_hurtbox()
	_update_color()
	_update_label()


func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE, State.CROUCHING, State.BLOCKING_STAND, State.BLOCKING_CROUCH:
			_grounded_process(delta)
		State.JUMPING:
			_airborne_process(delta)
		State.HITSTUN, State.BLOCKSTUN:
			_stun_process(delta)

	if flash_timer > 0.0:
		flash_timer -= delta
		sprite.modulate = flash_color
	else:
		sprite.modulate = state_color


func _grounded_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	state_timer -= delta
	if state_timer <= 0.0:
		_pick_random_state()


func _airborne_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	move_and_slide()

	if is_on_floor():
		velocity.y = 0.0
		_pick_random_state()    # will choose a grounded state
		return

	state_timer -= delta
	if state_timer <= 0.0:
		_pick_random_state()


func _stun_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	stun_timer -= delta
	if stun_timer <= 0.0:
		_change_state(State.IDLE)


func _pick_random_state() -> void:
	if always_block:
		# Alternate between standing and crouching block
		if current_state == State.BLOCKING_STAND:
			_change_state(State.BLOCKING_CROUCH)
		else:
			_change_state(State.BLOCKING_STAND)
		return

	var available: Array[State] = []
	if can_idle:
		available.append(State.IDLE)
	if can_crouch:
		available.append(State.CROUCHING)
	if can_jump:
		available.append(State.JUMPING)
	if can_block_stand:
		available.append(State.BLOCKING_STAND)
	if can_block_crouch:
		available.append(State.BLOCKING_CROUCH)

	if available.is_empty():
		_change_state(State.IDLE)   # fallback
		return

	var next = available[randi() % available.size()]
	_change_state(next)


func _change_state(new_state: State) -> void:
	current_state = new_state

	match new_state:
		State.IDLE:
			state_duration = randf_range(idle_min, idle_max)
			state_color = Color.WHITE
			base_hurtbox_size = Vector2(80, 160)
			base_hurtbox_position = Vector2(0, -80)
		State.CROUCHING:
			state_duration = randf_range(crouch_min, crouch_max)
			state_color = Color.DODGER_BLUE
			base_hurtbox_size = crouch_size
			base_hurtbox_position = crouch_position
		State.JUMPING:
			velocity.y = JUMP_VELOCITY
			state_duration = 999.0
			state_color = Color.YELLOW
			base_hurtbox_size = jump_size
			base_hurtbox_position = jump_position
		State.BLOCKING_STAND:
			state_duration = randf_range(block_stand_min, block_stand_max)
			state_color = Color.BLUE
			base_hurtbox_size = Vector2(80, 160)
			base_hurtbox_position = Vector2(0, -80)
		State.BLOCKING_CROUCH:
			state_duration = randf_range(block_crouch_min, block_crouch_max)
			state_color = Color.CORNFLOWER_BLUE   # slightly lighter blue
			base_hurtbox_size = crouch_size
			base_hurtbox_position = crouch_position
		State.HITSTUN, State.BLOCKSTUN:
			pass

	state_timer = state_duration
	_update_hurtbox()
	_update_color()
	_update_label()


func _update_hurtbox() -> void:
	hurtbox_collision.shape.size = base_hurtbox_size
	hurtbox_collision.position = base_hurtbox_position


func _update_color() -> void:
	if flash_timer <= 0.0:
		sprite.modulate = state_color


func _update_label() -> void:
	if not state_label:
		return
	state_label.text = State.keys()[current_state]


# ── Called by the attacker ──────────────────────────────────────
# Returns true if the hit was blocked (pushback trigger)
func take_hit(move_data: MoveData, attacker) -> bool:
	var was_blocking = (current_state == State.BLOCKING_STAND or current_state == State.BLOCKING_CROUCH)

	flash_timer = FLASH_DURATION

	if was_blocking:
		_change_state(State.BLOCKSTUN)
		stun_timer = (move_data.recovery + move_data.block_advantage) / 60.0
		if stun_timer < 0.0:
			stun_timer = 0.0
		return true
	else:
		_change_state(State.HITSTUN)
		stun_timer = move_data.hitstun / 60.0
		return false
