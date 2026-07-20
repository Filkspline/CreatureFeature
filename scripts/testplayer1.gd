extends CharacterBody2D
class_name Player

# ── Movement constants ──────────────────────────────────────────
const WALK_FORWARD_SPEED: float = 200.0
const WALK_BACKWARD_SPEED: float = 130.0
const JUMP_VELOCITY: float = -450.0
const GRAVITY: float = 980.0
const JUMP_APEX_THRESHOLD: float = 60.0

# ── Pushback ────────────────────────────────────────────────────
const PUSHBACK_DECELERATION: float = 600.0

# ── Animation frame durations ───────────────────────────────────
const IDLE_FRAME_DURATION: float = 0.2
const WALK_FRAME_DURATION: float = 0.12
const JUMP_FRAME_DURATION: float = 0.1
const LAND_FRAME_DURATION: float = 0.12
const CROUCH_TRANSITION_DURATION: float = 0.08
const CROUCH_LOOP_DURATION: float = 0.15
const CROUCH_STAND_DURATION: float = 0.08
const BLOCK_WARNING_FRAME_DURATION: float = 0.04

# ── Sprite frame counts ────────────────────────────────────────
const IDLE_FRAME_COUNT: int = 2
const WALK_FRAME_COUNT: int = 10

# ── Walk starting frames ──────────────────────────────────────
const WALK_FORWARD_START_FRAME: int = 6
const WALK_BACKWARD_START_FRAME: int = 3

# ── Jump spritesheet frames ─────────────────────────────────────
const JUMP_RISE_FRAMES: PackedInt32Array = [0, 1]
const JUMP_PEAK_FRAMES: PackedInt32Array = [2, 3, 4]
const JUMP_FALL_FRAME: PackedInt32Array = [4]
const JUMP_LAND_FRAMES: PackedInt32Array = [5, 6, 7]

# ── Crouch spritesheet frames ──────────────────────────────────
const CROUCH_TRANSITION_DOWN_FRAMES: PackedInt32Array = [0, 1]
const CROUCH_LOOP_FRAMES: PackedInt32Array = [2, 3]
const CROUCH_STAND_UP_FRAMES: PackedInt32Array = [4, 5]

# ── Block warning frames ───────────────────────────────────────
const BLOCK_WARNING_START_FRAMES: PackedInt32Array = [0, 1]
const BLOCK_WARNING_END_FRAME: int = 2

# ── Hurtbox vertical shrink ─────────────────────────────────────
const HURTBOX_VERTICAL_REDUCTION: float = 100.0

# ── Gatling buffer window ──────────────────────────────────────
const GATLING_BUFFER_FRAMES: int = 16

# ── Input buffer for direction changes ────────────────────────
const DIRECTION_BUFFER_TIME: float = 0.1

# ── States ──────────────────────────────────────────────────────
enum State { NEUTRAL, ATTACK, HITSTUN, BLOCKSTUN, KNOCKDOWN }

enum JumpPhase { RISE, PEAK, FALL }
enum Direction { NONE, LEFT, RIGHT }
enum CrouchPhase { NONE, TRANSITION_DOWN, LOOP, STAND_UP }
enum BlockWarningPhase { NONE, START, HOLD, END }

# Player always faces right; LEFT input = backward, RIGHT = forward.
var facing_right: bool = true
var state: State = State.NEUTRAL

# Horizontal speed locked in at jump start, ignores input while airborne.
var air_horizontal_velocity: float = 0.0

# Direction buffer to prevent idle flicker
var last_direction: int = Direction.NONE
var direction_buffer_timer: float = 0.0
var pending_direction: int = Direction.NONE

# ── Attack state ────────────────────────────────────────────────
@export var N5: MoveData
@export var N52: MoveData
@export var N4: MoveData
@export var N8: MoveData
@export var N6: MoveData
@export var N2: MoveData
@export var NA: MoveData
@export var S5: MoveData
@export var S4: MoveData
@export var S8: MoveData
@export var S6: MoveData
@export var S2: MoveData
@export var SA: MoveData

var all_moves: Dictionary = {}
var normal_moves: Dictionary = {}
var special_moves: Dictionary = {}

var current_move: MoveData = null
var attack_frame: int = 0
var opponent = null
var hit_connected: bool = false
var gatling_input_buffered: StringName = ""
var gatling_buffer_timer: int = 0

# Pushback state (active during attack)
var pushback_velocity_x: float = 0.0

# ── Stun timers ──────────────────────────────────────────────────
var stun_timer: float = 0.0

# ── Block warning state ────────────────────────────────────────
var block_warning_phase: int = BlockWarningPhase.NONE
var block_warning_frame_index: int = 0
var block_warning_timer: float = 0.0

# ── Animation state ────────────────────────────────────────────
@onready var idle_sprite: Sprite2D = $Idle
@onready var walk_backward_sprite: Sprite2D = $WalkBackward
@onready var walk_forward_sprite: Sprite2D = $WalkFoward
@onready var jump_sprite: Sprite2D = $Jump
@onready var crouch_sprite: Sprite2D = $Crouch
@onready var n5_sprite: Sprite2D = $N5
@onready var n52_sprite: Sprite2D = $N52
@onready var s5_sprite: Sprite2D = $S5
@onready var na_sprite: Sprite2D = $NA
@onready var mid_block_warning: Sprite2D = $MidBlockWarning
@onready var low_block_warning: Sprite2D = $LowBlockWarning
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Hurtbox shape will be duplicated at runtime so we can resize it safely.
@onready var hurtbox_shape: RectangleShape2D = $Hurtbox/CollisionShape2D.shape
var base_hurtbox_size: Vector2
var base_hurtbox_position: Vector2

var current_animation_name: String = ""
var current_sprite: Sprite2D
var current_frame_indices: PackedInt32Array = []
var frame_index: int = 0
var frame_timer: float = 0.0
var frame_duration: float = IDLE_FRAME_DURATION
var loop_animation: bool = true
var animation_finished: bool = false

# Landing & crouch logic
var is_landing: bool = false
var crouch_phase: int = CrouchPhase.NONE
var wants_to_crouch: bool = false


func _ready() -> void:
	$Hurtbox/CollisionShape2D.shape = hurtbox_shape.duplicate()
	hurtbox_shape = $Hurtbox/CollisionShape2D.shape
	base_hurtbox_size = hurtbox_shape.size
	base_hurtbox_position = $Hurtbox/CollisionShape2D.position

	n5_sprite.visible = false
	n52_sprite.visible = false
	s5_sprite.visible = false
	na_sprite.visible = false
	mid_block_warning.visible = false
	low_block_warning.visible = false

	_build_move_lookup()

	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self:
			opponent = p
			print("Opponent found: ", opponent.name)
			break
	if not opponent:
		print("No opponent found in 'players' group!")


func _build_move_lookup() -> void:
	var _add_move = func(move: MoveData, dict: Dictionary, key: String):
		if move:
			all_moves[move.move_name] = move
			dict[key] = move

	# Normals
	_add_move.call(N5, normal_moves, "neutral")
	_add_move.call(N4, normal_moves, "back")
	_add_move.call(N6, normal_moves, "forward")
	_add_move.call(N2, normal_moves, "crouching")
	_add_move.call(N8, normal_moves, "jumping")
	_add_move.call(NA, normal_moves, "aerial")
	_add_move.call(N52, normal_moves, "")

	# Specials
	_add_move.call(S5, special_moves, "neutral")
	_add_move.call(S4, special_moves, "back")
	_add_move.call(S6, special_moves, "forward")
	_add_move.call(S2, special_moves, "crouching")
	_add_move.call(S8, special_moves, "jumping")
	_add_move.call(SA, special_moves, "aerial")


func _physics_process(delta: float) -> void:
	match state:
		State.NEUTRAL:
			_neutral_process(delta)
		State.ATTACK:
			_attack_process(delta)
		State.HITSTUN:
			_hitstun_process(delta)
		State.BLOCKSTUN:
			_blockstun_process(delta)
		State.KNOCKDOWN:
			_knockdown_process(delta)


# ── Neutral state ────────────────────────────────────────────────
func _neutral_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	_apply_gravity(delta)
	_handle_jump()
	_handle_crouch_input()
	_handle_horizontal_movement(delta)
	move_and_slide()
	var just_landed := is_on_floor() and not was_on_floor
	_update_animation(delta, just_landed)
	_update_hurtbox()

	# Always update block‑ready visuals, even during crouch transitions
	_update_block_warning_visuals(delta)

	if is_landing or crouch_phase == CrouchPhase.TRANSITION_DOWN or crouch_phase == CrouchPhase.STAND_UP:
		return

	if Input.is_action_just_pressed("NormalP1"):
		var move = _resolve_move("normal")
		if move:
			_start_attack(move)

	if Input.is_action_just_pressed("SpecialP1"):
		var move = _resolve_move("special")
		if move:
			_start_attack(move)


# ── Block‑ready check ────────────────────────────────────────────
func _is_block_ready() -> bool:
	if not is_on_floor():
		return false
	var left_held = Input.is_action_pressed("LeftP1")
	if not left_held:
		return false
	# During crouch transition or loop, need Down+Back for low block
	if crouch_phase != CrouchPhase.NONE:
		return Input.is_action_pressed("DownP1")
	# Standing: back alone is standing block
	return true

# ── Block warning visuals (appear when block‑ready) ─────────────
func _update_block_warning_visuals(delta: float) -> void:
	var should_show = _is_block_ready()
	var is_crouching = crouch_phase != CrouchPhase.NONE
	var warning_sprite = low_block_warning if is_crouching else mid_block_warning
	var other_sprite = mid_block_warning if is_crouching else low_block_warning

	# Hide the other warning at all times
	other_sprite.visible = false

	# If the stance changed (crouch ↔ stand), reset the warning completely
	if should_show and block_warning_phase != BlockWarningPhase.NONE:
		# Check if the currently visible sprite is the wrong one for this stance
		if is_crouching and mid_block_warning.visible:
			mid_block_warning.visible = false
			block_warning_phase = BlockWarningPhase.NONE
		elif not is_crouching and low_block_warning.visible:
			low_block_warning.visible = false
			block_warning_phase = BlockWarningPhase.NONE

	# Not blocking and not already showing — nothing to do
	if not should_show and block_warning_phase == BlockWarningPhase.NONE:
		return

	# Start the warning animation
	if should_show and block_warning_phase == BlockWarningPhase.NONE:
		block_warning_phase = BlockWarningPhase.START
		block_warning_frame_index = 0
		block_warning_timer = 0.0
		warning_sprite.visible = true
		warning_sprite.frame = BLOCK_WARNING_START_FRAMES[0]

	# Continue through the animation phases
	elif should_show:
		match block_warning_phase:
			BlockWarningPhase.START:
				block_warning_timer += delta
				if block_warning_timer >= BLOCK_WARNING_FRAME_DURATION:
					block_warning_timer = 0.0
					block_warning_frame_index += 1
					if block_warning_frame_index >= BLOCK_WARNING_START_FRAMES.size():
						block_warning_phase = BlockWarningPhase.HOLD
						warning_sprite.frame = BLOCK_WARNING_START_FRAMES[BLOCK_WARNING_START_FRAMES.size() - 1]
					else:
						warning_sprite.frame = BLOCK_WARNING_START_FRAMES[block_warning_frame_index]

			BlockWarningPhase.HOLD:
				warning_sprite.frame = BLOCK_WARNING_START_FRAMES[BLOCK_WARNING_START_FRAMES.size() - 1]

			BlockWarningPhase.END:
				block_warning_phase = BlockWarningPhase.NONE
				_update_block_warning_visuals(0.0)
				return

	# Stop showing — play end frame
	elif not should_show and block_warning_phase != BlockWarningPhase.NONE:
		if block_warning_phase != BlockWarningPhase.END:
			block_warning_phase = BlockWarningPhase.END
			block_warning_timer = 0.0
			warning_sprite.frame = BLOCK_WARNING_END_FRAME
			warning_sprite.visible = true

		block_warning_timer += delta
		if block_warning_timer >= BLOCK_WARNING_FRAME_DURATION:
			warning_sprite.visible = false
			block_warning_phase = BlockWarningPhase.NONE

# ── Move resolver ────────────────────────────────────────────────
func _resolve_move(type: String) -> MoveData:
	var dict = normal_moves if type == "normal" else special_moves
	var key = ""
	if not is_on_floor():
		var aerial_move = dict.get("aerial", null)
		if aerial_move:
			return aerial_move
		key = "jumping"
	elif crouch_phase == CrouchPhase.LOOP:
		key = "crouching"
	else:
		var dir = _get_horizontal_input()
		if dir == 0.0:
			key = "neutral"
		elif (dir > 0.0) == facing_right:
			key = "forward"
		else:
			key = "back"
	return dict.get(key, null)


# ── Attack state ─────────────────────────────────────────────────
func _start_attack(move: MoveData) -> void:
	if not move:
		return

	state = State.ATTACK
	current_move = move
	attack_frame = 0
	hit_connected = false
	gatling_input_buffered = ""
	gatling_buffer_timer = 0
	pushback_velocity_x = 0.0

	# Hide locomotion sprites and block warnings
	idle_sprite.visible = false
	walk_backward_sprite.visible = false
	walk_forward_sprite.visible = false
	jump_sprite.visible = false
	crouch_sprite.visible = false
	mid_block_warning.visible = false
	low_block_warning.visible = false
	block_warning_phase = BlockWarningPhase.NONE

	# Hide all attack sprites
	n5_sprite.visible = false
	n52_sprite.visible = false
	s5_sprite.visible = false
	na_sprite.visible = false

	# Show the correct attack sprite
	match move.move_name:
		"N5":
			n5_sprite.visible = true
		"N52":
			n52_sprite.visible = true
		"S5":
			s5_sprite.visible = true
		"NA":
			na_sprite.visible = true

	current_animation_name = ""

	if animation_player.has_animation(move.animation_name):
		animation_player.play(move.animation_name)
		animation_player.seek(0, true)


func _attack_process(delta: float) -> void:
	var move_velocity := velocity

	# Slow fall during aerial attacks
	if not is_on_floor() and current_move:
		move_velocity.y *= 0.85
		move_velocity.y += GRAVITY * delta * 0.6
	else:
		move_velocity.y = 0.0

	# Advancing move with burst then fade
	if current_move and current_move.is_advancing and pushback_velocity_x == 0.0:
		if attack_frame == 1:
			move_velocity.x = current_move.advance_speed
		else:
			move_velocity.x = move_velocity.x * 0.85

	# Pushback overrides advancing
	if pushback_velocity_x != 0.0:
		move_velocity.x = pushback_velocity_x
		pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, PUSHBACK_DECELERATION * delta)

	velocity = move_velocity
	move_and_slide()

	attack_frame += 1

	if not current_move:
		return

	var anim_name = current_move.animation_name
	if not animation_player.has_animation(anim_name):
		_end_attack()
		return

	var anim_length = animation_player.get_animation(anim_name).length
	var total_frames = int(anim_length * 60.0)

	animation_player.seek(attack_frame / 60.0, true)

	if hit_connected:
		_try_gatling()

	if not hit_connected:
		_check_hit()

	if attack_frame >= total_frames:
		_end_attack()


func _try_gatling() -> void:
	if Input.is_action_just_pressed("NormalP1"):
		gatling_input_buffered = "NormalP1"
		gatling_buffer_timer = GATLING_BUFFER_FRAMES

	if gatling_input_buffered != "":
		gatling_buffer_timer -= 1
		if gatling_buffer_timer <= 0:
			gatling_input_buffered = ""
			gatling_buffer_timer = 0
			return

	if gatling_input_buffered == "NormalP1" and current_move.gatlings_into.size() > 0:
		var gatling_name = current_move.gatlings_into[0]
		if all_moves.has(gatling_name):
			_start_attack(all_moves[gatling_name])


func _end_attack() -> void:
	state = State.NEUTRAL
	attack_frame = 0
	current_move = null
	gatling_input_buffered = ""
	gatling_buffer_timer = 0
	pushback_velocity_x = 0.0

	# Hide all attack sprites
	n5_sprite.visible = false
	n52_sprite.visible = false
	s5_sprite.visible = false
	na_sprite.visible = false

	current_animation_name = ""
	current_sprite = null
	current_frame_indices = []
	frame_index = 0
	frame_timer = 0.0
	animation_finished = false

	# Restore correct sprite based on current state
	if is_on_floor():
		_update_grounded_animation()
	else:
		_update_jump_animation()


func _check_hit() -> void:
	if not opponent:
		return

	var hitbox = $Hitbox
	var hitbox_shape = hitbox.get_node("CollisionShape2D")
	if hitbox_shape.disabled:
		return

	var overlapping = hitbox.get_overlapping_areas()
	for area in overlapping:
		if area == opponent.get_node("Hurtbox") or area.get_parent() == opponent.get_node("Hurtbox"):
			var was_blocked = opponent.take_hit(current_move, self)
			hit_connected = true
			if was_blocked:
				_apply_pushback()
			return


func _apply_pushback() -> void:
	if not current_move or not opponent:
		return

	var dir_to_opponent = opponent.global_position.x - global_position.x
	var pushback_dir = -1.0 if dir_to_opponent > 0 else 1.0
	pushback_velocity_x = pushback_dir * current_move.pushback_on_block


# ── Hitstun state ────────────────────────────────────────────────
func _hitstun_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	stun_timer -= delta
	if stun_timer <= 0.0:
		state = State.NEUTRAL
		_restore_from_stun()


func _blockstun_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	stun_timer -= delta
	if stun_timer <= 0.0:
		state = State.NEUTRAL
		_restore_from_stun()


func _restore_from_stun() -> void:
	# Re‑enable locomotion sprites and reset block warning if needed
	if is_on_floor():
		_update_grounded_animation()
	else:
		_update_jump_animation()
	# Block warning will be handled by next _neutral_process


# ── Knockdown state ──────────────────────────────────────────────
func _knockdown_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()


# ── Taking a hit ─────────────────────────────────────────────────
func take_hit(move_data: MoveData, attacker) -> bool:
	var block_ready = _is_block_ready()
	if block_ready:
		state = State.BLOCKSTUN
		# blockstun = recovery + block_advantage (frames)
		var stun_frames = move_data.recovery + move_data.block_advantage
		if stun_frames < 0:
			stun_frames = 0
		stun_timer = stun_frames / 60.0
		return true
	else:
		state = State.HITSTUN
		stun_timer = move_data.hitstun / 60.0
		return false


# ── Gravity ──────────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += GRAVITY * delta


# ── Jump ─────────────────────────────────────────────────────────
func _handle_jump() -> void:
	if not is_on_floor() or crouch_phase != CrouchPhase.NONE:
		return
	if not Input.is_action_just_pressed("JumpP1"):
		return
	velocity.y = JUMP_VELOCITY
	air_horizontal_velocity = _get_horizontal_input() * _current_walk_speed()
	is_landing = false


# ── Crouch input ─────────────────────────────────────────────────
func _handle_crouch_input() -> void:
	wants_to_crouch = is_on_floor() and Input.is_action_pressed("DownP1")
	if wants_to_crouch and crouch_phase == CrouchPhase.NONE:
		_start_crouch_transition()
	elif not wants_to_crouch and crouch_phase == CrouchPhase.LOOP:
		_start_crouch_stand_up()

func _start_crouch_transition() -> void:
	crouch_phase = CrouchPhase.TRANSITION_DOWN
	_play_frames("crouch_down", crouch_sprite, CROUCH_TRANSITION_DOWN_FRAMES,
				CROUCH_TRANSITION_DURATION, false)

func _start_crouch_stand_up() -> void:
	crouch_phase = CrouchPhase.STAND_UP
	_play_frames("crouch_up", crouch_sprite, CROUCH_STAND_UP_FRAMES,
				CROUCH_STAND_DURATION, false)


# ── Horizontal movement ─────────────────────────────────────────
func _handle_horizontal_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.x = air_horizontal_velocity
		return
	if crouch_phase != CrouchPhase.NONE:
		velocity.x = 0.0
		return
	if is_landing:
		velocity.x = _get_horizontal_input() * _current_walk_speed()
		return

	var raw_direction := _get_raw_direction()
	if raw_direction != last_direction and raw_direction != Direction.NONE:
		pending_direction = raw_direction
		direction_buffer_timer = DIRECTION_BUFFER_TIME
	elif raw_direction == Direction.NONE:
		pending_direction = Direction.NONE
		direction_buffer_timer = 0.0
	elif raw_direction == last_direction:
		direction_buffer_timer = max(direction_buffer_timer - delta, 0.0)

	if direction_buffer_timer > 0.0 and pending_direction != Direction.NONE:
		velocity.x = _direction_to_float(pending_direction) * _speed_for_direction(pending_direction)
	else:
		last_direction = raw_direction
		velocity.x = _get_horizontal_input() * _current_walk_speed()


func _get_raw_direction() -> int:
	if Input.is_action_pressed("LeftP1"):
		return Direction.LEFT
	elif Input.is_action_pressed("RightP1"):
		return Direction.RIGHT
	return Direction.NONE

func _direction_to_float(dir: int) -> float:
	match dir:
		Direction.LEFT: return -1.0
		Direction.RIGHT: return 1.0
	return 0.0

func _get_horizontal_input() -> float:
	var dir := 0.0
	if Input.is_action_pressed("LeftP1"): dir -= 1.0
	if Input.is_action_pressed("RightP1"): dir += 1.0
	return dir

func _current_walk_speed() -> float:
	return WALK_BACKWARD_SPEED if _get_horizontal_input() < 0.0 else WALK_FORWARD_SPEED

func _speed_for_direction(dir: int) -> float:
	return WALK_BACKWARD_SPEED if dir == Direction.LEFT else WALK_FORWARD_SPEED


# ── Animation / sprite selection ────────────────────────────────
func _update_animation(delta: float, just_landed: bool) -> void:
	if just_landed:
		_play_frames("land", jump_sprite, JUMP_LAND_FRAMES, LAND_FRAME_DURATION, false)
		is_landing = true
		crouch_phase = CrouchPhase.NONE
	if is_landing and animation_finished:
		is_landing = false
	if crouch_phase != CrouchPhase.NONE:
		_step_current_frame(delta)
		_handle_crouch_phase_transitions()
		return
	if is_on_floor():
		if not is_landing:
			_update_grounded_animation()
	else:
		_update_jump_animation()
	_step_current_frame(delta)


func _update_grounded_animation() -> void:
	var direction := _get_horizontal_input()
	if direction == 0.0:
		_play_frames("idle", idle_sprite, _make_sequential_frames(IDLE_FRAME_COUNT),
					IDLE_FRAME_DURATION, true)
		last_direction = Direction.NONE
	else:
		_update_walk_animation(direction)

func _update_walk_animation(direction: float) -> void:
	if direction > 0.0:
		_play_frames("walk_forward", walk_forward_sprite,
					_make_walk_frames(WALK_FORWARD_START_FRAME), WALK_FRAME_DURATION, true)
	else:
		_play_frames("walk_backward", walk_backward_sprite,
					_make_walk_frames(WALK_BACKWARD_START_FRAME), WALK_FRAME_DURATION, true)

func _update_jump_animation() -> void:
	match _get_jump_phase():
		JumpPhase.RISE:
			_play_frames("jump_rise", jump_sprite, JUMP_RISE_FRAMES, JUMP_FRAME_DURATION, false)
		JumpPhase.PEAK:
			_play_frames("jump_peak", jump_sprite, JUMP_PEAK_FRAMES, JUMP_FRAME_DURATION, false)
		JumpPhase.FALL:
			_play_frames("jump_fall", jump_sprite, JUMP_FALL_FRAME, JUMP_FRAME_DURATION, false)

func _get_jump_phase() -> JumpPhase:
	if velocity.y < -JUMP_APEX_THRESHOLD:
		return JumpPhase.RISE
	if velocity.y > JUMP_APEX_THRESHOLD:
		return JumpPhase.FALL
	return JumpPhase.PEAK


# ── Crouch phase transitions ────────────────────────────────────
func _handle_crouch_phase_transitions() -> void:
	match crouch_phase:
		CrouchPhase.TRANSITION_DOWN:
			if animation_finished:
				if wants_to_crouch:
					crouch_phase = CrouchPhase.LOOP
					_play_frames("crouch_loop", crouch_sprite, CROUCH_LOOP_FRAMES,
								CROUCH_LOOP_DURATION, true)
				else:
					_start_crouch_stand_up()
		CrouchPhase.LOOP:
			if not wants_to_crouch:
				_start_crouch_stand_up()
		CrouchPhase.STAND_UP:
			if animation_finished:
				crouch_phase = CrouchPhase.NONE


# ── Generic frame player ─────────────────────────────────────────
func _make_sequential_frames(count: int, start_frame: int = 0) -> PackedInt32Array:
	var frames := PackedInt32Array()
	for i in range(count):
		frames.append((start_frame + i) % count)
	return frames

func _make_walk_frames(start_frame: int) -> PackedInt32Array:
	var frames := PackedInt32Array()
	for i in range(WALK_FRAME_COUNT):
		frames.append((start_frame + i) % WALK_FRAME_COUNT)
	return frames

func _play_frames(animation_name: String, sprite: Sprite2D,
				 frames: PackedInt32Array, duration: float, loop: bool) -> void:
	if current_animation_name == animation_name:
		return
	_show_only(sprite)
	current_animation_name = animation_name
	current_sprite = sprite
	current_frame_indices = frames
	frame_index = 0
	frame_timer = 0.0
	frame_duration = duration
	loop_animation = loop
	animation_finished = false
	_apply_current_frame()

func _show_only(sprite: Sprite2D) -> void:
	idle_sprite.visible = sprite == idle_sprite
	walk_backward_sprite.visible = sprite == walk_backward_sprite
	walk_forward_sprite.visible = sprite == walk_forward_sprite
	jump_sprite.visible = sprite == jump_sprite
	crouch_sprite.visible = sprite == crouch_sprite

func _step_current_frame(delta: float) -> void:
	if current_frame_indices.is_empty():
		return
	frame_timer += delta
	if frame_timer < frame_duration:
		return
	frame_timer -= frame_duration
	frame_index += 1
	if frame_index >= current_frame_indices.size():
		frame_index = current_frame_indices.size() - 1
		if loop_animation:
			frame_index = 0
		else:
			animation_finished = true
	_apply_current_frame()

func _apply_current_frame() -> void:
	current_sprite.frame = current_frame_indices[frame_index]


# ── Hurtbox reshaping ────────────────────────────────────────────
func _update_hurtbox() -> void:
	var new_size := base_hurtbox_size
	var new_pos := base_hurtbox_position
	var reduction := HURTBOX_VERTICAL_REDUCTION

	if not is_on_floor():
		new_size.y = base_hurtbox_size.y - reduction
		new_pos.y = base_hurtbox_position.y - reduction * 0.5
	elif crouch_phase != CrouchPhase.NONE:
		new_size.y = base_hurtbox_size.y - reduction
		new_pos.y = base_hurtbox_position.y + reduction * 0.5

	hurtbox_shape.size = new_size
	$Hurtbox/CollisionShape2D.position = new_pos
