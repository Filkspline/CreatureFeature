extends CharacterBody2D
class_name DefenseTester

# ── Visuals ──────────────────────────────────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var hurtbox_collision: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_collision: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var state_label: Label = $Label if has_node("Label") else null

var base_color: Color = Color.WHITE
var state_color: Color = Color.WHITE
var flash_color: Color = Color.RED
var is_flashing: bool = false
var flash_timer: float = 0.0
const FLASH_DURATION: float = 0.15

# ── Attack state ────────────────────────────────────────────────
var is_attacking: bool = false
var attack_timer: float = 0.0
var attack_duration: float = 0.3
var attack_active: bool = false
var attack_active_timer: float = 0.0
var attack_active_duration: float = 0.1
var attack_cooldown: float = 0.0
var attack_color: Color = Color.ORANGE

# ── Debug ──────────────────────────────────────────────────────
var debug_attack_hit: bool = false
var debug_attack_miss: bool = false
var debug_timer: float = 0.0

# ── States ──────────────────────────────────────────────────────
enum State {
	IDLE,
	CROUCHING,
	JUMPING,
	ATTACKING_STAND,
	ATTACKING_CROUCH,
	ATTACKING_JUMP,
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
@export var can_attack: bool = true

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

# ── Attack settings ────────────────────────────────────────────
@export_group("Attack Settings")
@export var attack_chance: float = 0.3

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
	hitbox_collision.disabled = true
	
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	hitbox.area_exited.connect(_on_hitbox_area_exited)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.body_exited.connect(_on_hitbox_body_exited)
	
	if not always_block:
		_change_state(State.IDLE)
	else:
		_change_state(State.BLOCKING_STAND)
	_update_hurtbox()
	_update_color()
	_update_label()


func _physics_process(delta: float) -> void:
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	
	if debug_timer > 0.0:
		debug_timer -= delta
	elif debug_timer <= 0.0 and (debug_attack_hit or debug_attack_miss):
		debug_attack_hit = false
		debug_attack_miss = false
	
	match current_state:
		State.IDLE, State.CROUCHING, State.BLOCKING_STAND, State.BLOCKING_CROUCH:
			_grounded_process(delta)
		State.ATTACKING_STAND, State.ATTACKING_CROUCH:
			_grounded_attack_process(delta)
		State.JUMPING:
			_airborne_process(delta)
		State.ATTACKING_JUMP:
			_airborne_attack_process(delta)
		State.HITSTUN, State.BLOCKSTUN:
			_stun_process(delta)

	if flash_timer > 0.0:
		flash_timer -= delta
		sprite.modulate = flash_color
	elif is_attacking and attack_active:
		sprite.modulate = attack_color
	elif debug_attack_hit:
		sprite.modulate = Color.GREEN
	elif debug_attack_miss:
		sprite.modulate = Color.RED
	else:
		sprite.modulate = state_color


func _grounded_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	state_timer -= delta
	if state_timer <= 0.0:
		_pick_random_state()
	elif can_attack and attack_cooldown <= 0.0 and randf() < attack_chance * delta:
		_start_attack()


func _grounded_attack_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_update_attack(delta)
	if not is_attacking:
		_pick_random_state()


func _airborne_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	move_and_slide()

	if is_on_floor():
		velocity.y = 0.0
		_pick_random_state()
		return

	state_timer -= delta
	if state_timer <= 0.0:
		_pick_random_state()
	elif can_attack and attack_cooldown <= 0.0 and randf() < attack_chance * delta:
		_start_attack()


func _airborne_attack_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	move_and_slide()
	_update_attack(delta)
	
	if is_on_floor():
		velocity.y = 0.0
		_end_attack()
		_pick_random_state()
	elif not is_attacking:
		_change_state(State.JUMPING)


func _stun_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	stun_timer -= delta
	if stun_timer <= 0.0:
		_change_state(State.IDLE)


func _start_attack() -> void:
	is_attacking = true
	attack_timer = 0.0
	attack_active = false
	debug_attack_hit = false
	debug_attack_miss = false
	
	print("DefenseTester starting attack")
	
	match current_state:
		State.IDLE, State.BLOCKING_STAND:
			_change_state(State.ATTACKING_STAND)
		State.CROUCHING, State.BLOCKING_CROUCH:
			_change_state(State.ATTACKING_CROUCH)
		State.JUMPING:
			_change_state(State.ATTACKING_JUMP)


func _update_attack(delta: float) -> void:
	attack_timer += delta
	
	if not attack_active and attack_timer >= attack_duration * 0.3:
		attack_active = true
		attack_active_timer = 0.0
		hitbox_collision.disabled = false
		print("Hitbox ACTIVE")
		_check_hit()
	
	if attack_active:
		attack_active_timer += delta
		if attack_active_timer >= attack_active_duration:
			hitbox_collision.disabled = true
			print("Hitbox DEACTIVATED")
	
	if attack_timer >= attack_duration:
		_end_attack()


func _check_hit() -> void:
	var overlapping_areas = hitbox.get_overlapping_areas()
	print("Checking ", overlapping_areas.size(), " overlapping areas")
	
	var hit_applied = false
	
	for area in overlapping_areas:
		var parent = area.get_parent()
		if parent == self:
			continue
		if area.name == "Hurtbox" and parent.has_method("take_hit"):
			print("Hitting ", parent.name)
			
			# Create MoveData with FRAME COUNTS (not seconds)
			var move_data = MoveData.new()
			move_data.hitstun = 25           # 25 frames of hitstun (~0.4s)
			move_data.recovery = 10          # 10 frames recovery
			move_data.block_advantage = -5   # -5 frames block advantage
			move_data.pushback_on_block = 150.0
			
			parent.take_hit(move_data, self)
			hit_applied = true
			debug_attack_hit = true
			debug_timer = 0.5
			break
	
	if not hit_applied:
		debug_attack_miss = true
		debug_timer = 0.5


func _end_attack() -> void:
	is_attacking = false
	attack_active = false
	hitbox_collision.disabled = true
	attack_cooldown = 0.5
	
	match current_state:
		State.ATTACKING_STAND:
			_change_state(State.IDLE)
		State.ATTACKING_CROUCH:
			_change_state(State.CROUCHING)
		State.ATTACKING_JUMP:
			if not is_on_floor():
				_change_state(State.JUMPING)
			else:
				_change_state(State.IDLE)


func _on_hitbox_area_entered(area: Area2D) -> void:
	if is_attacking and attack_active and area.name == "Hurtbox":
		var parent = area.get_parent()
		if parent != self and parent.has_method("take_hit"):
			print("Hit on enter!")
			var move_data = MoveData.new()
			move_data.hitstun = 25
			move_data.recovery = 10
			move_data.block_advantage = -5
			move_data.pushback_on_block = 150.0
			parent.take_hit(move_data, self)
			debug_attack_hit = true
			debug_timer = 0.5

func _on_hitbox_area_exited(area: Area2D) -> void:
	pass

func _on_hitbox_body_entered(body: Node2D) -> void:
	pass

func _on_hitbox_body_exited(body: Node2D) -> void:
	pass


func _pick_random_state() -> void:
	if always_block:
		if current_state == State.BLOCKING_STAND:
			_change_state(State.BLOCKING_CROUCH)
		else:
			_change_state(State.BLOCKING_STAND)
		return

	var available: Array[State] = []
	if can_idle: available.append(State.IDLE)
	if can_crouch: available.append(State.CROUCHING)
	if can_jump: available.append(State.JUMPING)
	if can_block_stand: available.append(State.BLOCKING_STAND)
	if can_block_crouch: available.append(State.BLOCKING_CROUCH)

	if available.is_empty():
		_change_state(State.IDLE)
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
		State.ATTACKING_STAND:
			state_duration = attack_duration
			state_color = Color.WHITE
		State.ATTACKING_CROUCH:
			state_duration = attack_duration
			state_color = Color.DODGER_BLUE
		State.ATTACKING_JUMP:
			state_duration = attack_duration
			state_color = Color.YELLOW
		State.BLOCKING_STAND:
			state_duration = randf_range(block_stand_min, block_stand_max)
			state_color = Color.BLUE
		State.BLOCKING_CROUCH:
			state_duration = randf_range(block_crouch_min, block_crouch_max)
			state_color = Color.CORNFLOWER_BLUE
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
	if flash_timer <= 0.0 and not (is_attacking and attack_active) and not debug_attack_hit and not debug_attack_miss:
		sprite.modulate = state_color


func _update_label() -> void:
	if not state_label:
		return
	state_label.text = State.keys()[current_state]


func take_hit(move_data: MoveData, attacker) -> bool:
	var was_blocking = (current_state == State.BLOCKING_STAND or current_state == State.BLOCKING_CROUCH)

	flash_timer = FLASH_DURATION
	
	if is_attacking:
		_end_attack()

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
