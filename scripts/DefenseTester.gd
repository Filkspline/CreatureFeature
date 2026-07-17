extends CharacterBody2D
class_name DefenseTester

# ── Visuals ──────────────────────────────────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var hurtbox_collision: CollisionShape2D = $Hurtbox/CollisionShape2D

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
var current_state: State = State.IDLE
var state_timer: float = 0.0
var state_duration: float = 0.0

# Stun timers
var stun_timer: float = 0.0

# ── Movement ────────────────────────────────────────────────────
const GRAVITY: float = 980.0
const JUMP_VELOCITY: float = -400.0

# ── Hurtbox dimensions (adjust to match your character) ────────
var base_hurtbox_size: Vector2 = Vector2(80, 160)
var base_hurtbox_position: Vector2 = Vector2(0, -80)

var crouch_size: Vector2 = Vector2(80, 110)
var crouch_position: Vector2 = Vector2(0, -55)

var jump_size: Vector2 = Vector2(80, 120)
var jump_position: Vector2 = Vector2(0, -100)


func _ready() -> void:
	add_to_group("players")
	
	# Set initial state
	_change_state(State.IDLE)
	_update_hurtbox()
	_update_color()


func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE, State.CROUCHING, State.BLOCKING_STAND, State.BLOCKING_CROUCH:
			_grounded_process(delta)
		State.JUMPING:
			_airborne_process(delta)
		State.HITSTUN, State.BLOCKSTUN:
			_stun_process(delta)
	
	# Flash handling
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
		_change_state(State.IDLE)
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
	var r := randf()
	
	if r < 0.3:
		_change_state(State.IDLE)
	elif r < 0.5:
		_change_state(State.CROUCHING)
	elif r < 0.65:
		_change_state(State.JUMPING)
	elif r < 0.8:
		_change_state(State.BLOCKING_STAND)
	else:
		_change_state(State.BLOCKING_CROUCH)


func _change_state(new_state: State) -> void:
	current_state = new_state
	
	match new_state:
		State.IDLE:
			state_duration = randf_range(0.8, 2.0)
			state_color = Color.WHITE
			base_hurtbox_size = Vector2(80, 160)
			base_hurtbox_position = Vector2(0, -80)
		State.CROUCHING:
			state_duration = randf_range(0.5, 1.5)
			state_color = Color.DODGER_BLUE
			base_hurtbox_size = crouch_size
			base_hurtbox_position = crouch_position
		State.JUMPING:
			velocity.y = JUMP_VELOCITY
			state_duration = 999.0   # will be interrupted by landing
			state_color = Color.YELLOW
			base_hurtbox_size = jump_size
			base_hurtbox_position = jump_position
		State.BLOCKING_STAND:
			state_duration = randf_range(0.6, 1.8)
			state_color = Color.GREEN
			base_hurtbox_size = Vector2(80, 160)
			base_hurtbox_position = Vector2(0, -80)
		State.BLOCKING_CROUCH:
			state_duration = randf_range(0.6, 1.8)
			state_color = Color.CYAN
			base_hurtbox_size = crouch_size
			base_hurtbox_position = crouch_position
		State.HITSTUN, State.BLOCKSTUN:
			# stun duration set separately
			pass
	
	state_timer = state_duration
	_update_hurtbox()
	_update_color()


func _update_hurtbox() -> void:
	hurtbox_collision.shape.size = base_hurtbox_size
	hurtbox_collision.position = base_hurtbox_position


func _update_color() -> void:
	if flash_timer <= 0.0:
		sprite.modulate = state_color


# ── Called by the attacker ──────────────────────────────────────
func take_hit(move_data: MoveData, attacker: Player) -> void:
	var was_blocking = (current_state == State.BLOCKING_STAND or current_state == State.BLOCKING_CROUCH)
	
	# Visual feedback
	flash_timer = FLASH_DURATION
	
	if was_blocking:
		_change_state(State.BLOCKSTUN)
		stun_timer = (move_data.recovery + move_data.block_advantage) / 60.0
		if stun_timer < 0.0:
			stun_timer = 0.0
	else:
		_change_state(State.HITSTUN)
		stun_timer = move_data.hitstun / 60.0
	
	# You can add knockback later if needed
	print("Defense tester hit! State: ", State.keys()[current_state], " stun frames: ", stun_timer * 60.0)
