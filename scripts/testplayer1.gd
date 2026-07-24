extends CharacterBody2D
class_name Player

# ── Movement constants ──────────────────────────────────────────
const WALK_FORWARD_SPEED: float = 200.0
const WALK_BACKWARD_SPEED: float = 130.0
const JUMP_VELOCITY: float = -550.0
const GRAVITY: float = 1180.0
const JUMP_APEX_THRESHOLD: float = 60.0

# ── Pushback ────────────────────────────────────────────────────
const PUSHBACK_DECELERATION: float = 600.0

# ── Hurtbox vertical shrink ─────────────────────────────────────
const HURTBOX_VERTICAL_REDUCTION: float = 50.0

# ── Gatling buffer window ──────────────────────────────────────
const GATLING_BUFFER_FRAMES: int = 16

# ── Input buffer for direction changes ────────────────────────
const DIRECTION_BUFFER_TIME: float = 0.1

# ── Debug ────────────────────────────────────────────────────────
# Flip this to false to silence all debug output at once.
const DEBUG: bool = true

# ── States ──────────────────────────────────────────────────────
enum State { NEUTRAL, ATTACK, HITSTUN, BLOCKSTUN, KNOCKDOWN }
enum JumpPhase { RISE, PEAK, FALL }
enum Direction { NONE, LEFT, RIGHT }
enum CrouchPhase { NONE, TRANSITION_DOWN, LOOP, STAND_UP }
enum BlockWarningPhase { NONE, START, HOLD, END }

# Animations that should NOT loop (will be paused on finish)
const HOLD_ON_FINISH_ANIMS: Array[String] = [
	"jump_rise", "jump_peak", "jump_land",
	"crouch_down", "crouch_up",
	"crouch_hit", "mid_hit"
]

# Player always faces right; LEFT input = backward, RIGHT = forward.
var facing_right: bool = true
var state: State = State.NEUTRAL :
	set(new_state):
		if state != new_state:
			_dbg("[STATE] %s -> %s" % [State.keys()[state], State.keys()[new_state]])
			state = new_state
			EventBus.player_state_changed.emit(state)

signal landed
signal hitstun_finished

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

# ── Aerial attack tracking ──────────────────────────────────────
var has_used_aerial: bool = false

# ── Stun timers ──────────────────────────────────────────────────
var stun_timer: float = 0.0
# True for exactly the physics frame a hit/block stun starts. Prevents the
# stun timer from being decremented on the same frame it was set, which
# could otherwise let very short stuns (e.g. plus-on-block normals) expire
# before the block/hit reaction animation ever gets a frame to render.
var stun_just_started: bool = false

# ── Block state tracking ────────────────────────────────────────
var is_blocking_low: bool = false

# ── Block warning state ────────────────────────────────────────
var block_warning_phase: int = BlockWarningPhase.NONE
var block_warning_frame_index: int = 0
var block_warning_timer: float = 0.0
var block_warning_is_crouching: bool = false
const BLOCK_WARNING_FRAME_DURATION: float = 0.04
const BLOCK_WARNING_START_FRAMES: PackedInt32Array = [0, 1]
const BLOCK_WARNING_END_FRAME: int = 2

# ── AnimationPlayer ─────────────────────────────────────────────
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var idle_sprite: Sprite2D = $Idle
@onready var walk_backward_sprite: Sprite2D = $WalkBackward
@onready var walk_forward_sprite: Sprite2D = $WalkForward
@onready var jump_sprite: Sprite2D = $Jump
@onready var crouch_sprite: Sprite2D = $Crouch
@onready var n5_sprite: Sprite2D = $N5
@onready var n52_sprite: Sprite2D = $N52
@onready var s5_sprite: Sprite2D = $S5
@onready var na_sprite: Sprite2D = $NA
@onready var mid_block_warning: Sprite2D = $MidBlockWarning
@onready var low_block_warning: Sprite2D = $LowBlockWarning
@onready var block_idle_sprite: Sprite2D = $BlockIdle
@onready var crouch_block_idle_sprite: Sprite2D = $CrouchBlockIdle
@onready var crouch_hit_sprite: Sprite2D = $CrouchHit
@onready var mid_hit_sprite: Sprite2D = $MidHit

# Hurtbox shape duplicated at runtime
@onready var hurtbox_shape: RectangleShape2D = $Hurtbox/MainHurtbox.shape
var base_hurtbox_size: Vector2
var base_hurtbox_position: Vector2

# Landing & crouch logic
var is_landing: bool = false
var crouch_phase: int = CrouchPhase.NONE :
	set(new_phase):
		if crouch_phase != new_phase:
			_dbg("[CROUCH PHASE] %s -> %s" % [CrouchPhase.keys()[crouch_phase], CrouchPhase.keys()[new_phase]])
		crouch_phase = new_phase
		EventBus.player_crouching = (new_phase != CrouchPhase.NONE)

var wants_to_crouch: bool = false

# Current animation key (avoids restarts)
var current_anim: String = ""


# ── Debug helper ──────────────────────────────────────────────────
# Central choke point for all debug logging so it can be silenced with a
# single flag instead of being sprinkled across every frame.
func _dbg(msg: String) -> void:
	if DEBUG:
		print(msg)


func _ready() -> void:
	$Hurtbox/MainHurtbox.shape = hurtbox_shape.duplicate()
	hurtbox_shape = $Hurtbox/MainHurtbox.shape
	base_hurtbox_size = hurtbox_shape.size
	base_hurtbox_position = $Hurtbox/MainHurtbox.position

	# Hide attack sprites initially
	n5_sprite.visible = false
	n52_sprite.visible = false
	s5_sprite.visible = false
	na_sprite.visible = false
	# Blocking sprites off
	mid_block_warning.visible = false
	low_block_warning.visible = false
	block_idle_sprite.visible = false
	crouch_block_idle_sprite.visible = false
	# Hit-reaction sprites off
	crouch_hit_sprite.visible = false
	mid_hit_sprite.visible = false

	_build_move_lookup()

	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self:
			opponent = p
			_dbg("[SETUP] Opponent found: %s" % opponent.name)
			break
	if not opponent:
		push_warning("[SETUP] No opponent found in 'players' group!")

	# Configure loop modes for all animations
	for anim_name in animation_player.get_animation_list():
		var anim = animation_player.get_animation(anim_name)
		if anim:
			if anim_name in HOLD_ON_FINISH_ANIMS:
				anim.loop_mode = Animation.LOOP_NONE
			elif anim_name in ["block_idle", "crouch_block_idle", "crouch_idle", "idle", "walk_forward", "walk_backward"]:
				anim.loop_mode = Animation.LOOP_LINEAR
			_dbg("[ANIM SETUP] '%s' -> loop_mode=%s length=%.4f" % [anim_name, anim.loop_mode, anim.length])
		else:
			push_warning("[ANIM SETUP] '%s' returned null Animation resource!" % anim_name)

	# Connect signal for animation finished
	animation_player.animation_finished.connect(_on_animation_finished)

	# Reset everything to default frame states
	animation_player.play("RESET")
	animation_player.seek(0.0, true)

	# Start in idle
	_play_anim("idle", idle_sprite)


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


# ──────────────────────────────────────────────────────────────────
#  Main physics loop
# ──────────────────────────────────────────────────────────────────
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

	# Update EventBus with live data
	EventBus.player_position = global_position
	EventBus.player_velocity = velocity
	EventBus.player_is_airborne = not is_on_floor()


# ── Neutral state ────────────────────────────────────────────────
func _neutral_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	_apply_gravity(delta)
	_handle_jump()
	_handle_crouch_input()
	_handle_horizontal_movement(delta)
	move_and_slide()
	var just_landed := is_on_floor() and not was_on_floor

	if just_landed:
		has_used_aerial = false
		is_landing = true
		_dbg("[LANDED] emitting landed signal")
		landed.emit()
		_play_anim("jump_land", jump_sprite, true)

	_update_animation(just_landed)
	_update_hurtbox()
	_update_block_warning_visuals(delta)

	if Input.is_action_just_pressed("NormalP1"):
		var move = _resolve_move("normal")
		if move:
			_start_attack(move)

	if Input.is_action_just_pressed("SpecialP1"):
		var move = _resolve_move("special")
		if move:
			_start_attack(move)


func _is_block_ready() -> bool:
	if not is_on_floor():
		return false
	var left_held = Input.is_action_pressed("LeftP1")
	if not left_held:
		return false
	if crouch_phase != CrouchPhase.NONE:
		return Input.is_action_pressed("DownP1")
	return true


# ── Block warning (manual, no animation available) ──────────────
func _update_block_warning_visuals(delta: float) -> void:
	var should_show = _is_block_ready()
	var is_crouching = crouch_phase != CrouchPhase.NONE

	if block_warning_phase != BlockWarningPhase.NONE and is_crouching != block_warning_is_crouching:
		_dbg("[BLOCK WARN] crouch state changed mid-warning (was crouching=%s, now=%s) -> reset" % [block_warning_is_crouching, is_crouching])
		_reset_block_warning()

	if not should_show and block_warning_phase == BlockWarningPhase.NONE:
		return

	var warning_sprite = low_block_warning if is_crouching else mid_block_warning
	var other_sprite = mid_block_warning if is_crouching else low_block_warning
	other_sprite.visible = false

	if should_show and block_warning_phase == BlockWarningPhase.NONE:
		block_warning_phase = BlockWarningPhase.START
		block_warning_frame_index = 0
		block_warning_timer = 0.0
		block_warning_is_crouching = is_crouching
		warning_sprite.visible = true
		warning_sprite.frame = BLOCK_WARNING_START_FRAMES[0]
		_dbg("[BLOCK WARN] START new warning (crouching=%s)" % is_crouching)

	elif should_show:
		warning_sprite.visible = true
		match block_warning_phase:
			BlockWarningPhase.START:
				block_warning_timer += delta
				if block_warning_timer >= BLOCK_WARNING_FRAME_DURATION:
					block_warning_timer = 0.0
					block_warning_frame_index += 1
					if block_warning_frame_index >= BLOCK_WARNING_START_FRAMES.size():
						block_warning_phase = BlockWarningPhase.HOLD
						warning_sprite.frame = BLOCK_WARNING_START_FRAMES[BLOCK_WARNING_START_FRAMES.size() - 1]
						_dbg("[BLOCK WARN] START -> HOLD")
					else:
						warning_sprite.frame = BLOCK_WARNING_START_FRAMES[block_warning_frame_index]

			BlockWarningPhase.HOLD:
				warning_sprite.frame = BLOCK_WARNING_START_FRAMES[BLOCK_WARNING_START_FRAMES.size() - 1]

			BlockWarningPhase.END:
				_dbg("[BLOCK WARN] should_show became true again while still in END -> reset")
				_reset_block_warning()

	elif not should_show and block_warning_phase != BlockWarningPhase.NONE:
		if block_warning_phase != BlockWarningPhase.END:
			block_warning_phase = BlockWarningPhase.END
			block_warning_timer = 0.0
			warning_sprite.frame = BLOCK_WARNING_END_FRAME
			warning_sprite.visible = true
			_dbg("[BLOCK WARN] HOLD -> END")

		block_warning_timer += delta
		if block_warning_timer >= BLOCK_WARNING_FRAME_DURATION:
			_dbg("[BLOCK WARN] END finished -> reset")
			_reset_block_warning()

func _reset_block_warning() -> void:
	mid_block_warning.visible = false
	low_block_warning.visible = false
	block_warning_phase = BlockWarningPhase.NONE
	block_warning_is_crouching = false


# ── Attack resolve / start ───────────────────────────────────────
func _resolve_move(type: String) -> MoveData:
	var dict = normal_moves if type == "normal" else special_moves
	var key = ""
	if not is_on_floor():
		if has_used_aerial:
			return null
		var aerial_move = dict.get("aerial", null)
		if aerial_move:
			has_used_aerial = true
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

	var move = dict.get(key, null)
	if move == null and key != "neutral" and key != "crouching" and key != "jumping":
		move = dict.get("neutral", null)
	return move


func _start_attack(move: MoveData) -> void:
	if not move:
		return

	_dbg("[ATTACK] starting move '%s'" % move.move_name)

	state = State.ATTACK
	current_move = move
	attack_frame = 0
	hit_connected = false
	gatling_input_buffered = ""
	gatling_buffer_timer = 0

	if is_on_floor():
		pushback_velocity_x = 0.0

	crouch_phase = CrouchPhase.NONE
	wants_to_crouch = false
	is_landing = false

	_hide_all_sprites()
	_reset_block_warning()

	match move.move_name:
		"N5":
			n5_sprite.visible = true
		"N52":
			n52_sprite.visible = true
		"S5":
			s5_sprite.visible = true
		"NA":
			na_sprite.visible = true

	EventBus.player_attack_started.emit(move.move_name)

	if animation_player.has_animation(move.animation_name):
		animation_player.play(move.animation_name)
		animation_player.seek(0, true)
		current_anim = move.animation_name


# ── Attack process ───────────────────────────────────────────────
func _attack_process(delta: float) -> void:
	var move_velocity := velocity

	if not is_on_floor() and current_move:
		move_velocity.y *= 0.85
		move_velocity.y += GRAVITY * delta * 0.6
	else:
		move_velocity.y = 0.0

	if current_move and current_move.is_advancing and pushback_velocity_x == 0.0:
		if attack_frame == 1:
			move_velocity.x = current_move.advance_speed
		else:
			move_velocity.x = move_velocity.x * 0.85

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
			_dbg("[GATLING] buffered input confirmed -> canceling into '%s'" % gatling_name)
			_start_attack(all_moves[gatling_name])


func _end_attack() -> void:
	var was_airborne := not is_on_floor()
	_dbg("[END ATTACK] current_anim was '%s' | was_airborne=%s velocity.y=%.1f" % [current_anim, was_airborne, velocity.y])

	state = State.NEUTRAL
	attack_frame = 0
	current_move = null
	gatling_input_buffered = ""
	gatling_buffer_timer = 0

	if was_airborne:
		air_horizontal_velocity = velocity.x

	_hide_attack_sprites()
	_update_animation(false)


func _check_hit() -> void:
	if not opponent:
		return

	var hitbox = $Hitbox
	var hitbox_shape = hitbox.get_node("MainHitbox")
	if hitbox_shape.disabled:
		return

	var overlapping = hitbox.get_overlapping_areas()
	for area in overlapping:
		if area == opponent.get_node("Hurtbox") or area.get_parent() == opponent.get_node("Hurtbox"):
			var was_blocked = opponent.take_hit(current_move, self)
			hit_connected = true
			_dbg("[HIT] '%s' connected on opponent | blocked=%s" % [current_move.move_name, was_blocked])
			EventBus.player_hit_landed.emit(current_move.move_name, was_blocked)
			if was_blocked:
				_apply_pushback()
			return


func _apply_pushback() -> void:
	if not current_move or not opponent:
		return

	var dir_to_opponent = opponent.global_position.x - global_position.x
	var pushback_dir = -1.0 if dir_to_opponent > 0 else 1.0
	pushback_velocity_x = pushback_dir * current_move.pushback_on_block
	_dbg("[PUSHBACK] applying %.1f px/s (dir=%.0f)" % [pushback_velocity_x, pushback_dir])

	if not is_on_floor():
		air_horizontal_velocity = pushback_velocity_x


# ── Hitstun / Blockstun / Knockdown ──────────────────────────────
func _hitstun_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	# Skip the decrement on the very frame stun started — see comment on
	# stun_just_started for why this matters.
	if stun_just_started:
		stun_just_started = false
	else:
		stun_timer -= delta

	if stun_timer <= 0.0:
		_dbg("[HITSTUN] timer expired -> emitting hitstun_finished")
		state = State.NEUTRAL
		hitstun_finished.emit()  # wakes freeze_until_hitstun_recovery() if crouch_hit/mid_hit is paused there
		_update_animation(false)


func _blockstun_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	if is_blocking_low:
		_play_anim("crouch_block_idle", crouch_block_idle_sprite)
		EventBus.player_blocking_low = true
	else:
		_play_anim("block_idle", block_idle_sprite)
		EventBus.player_blocking_low = false

	# Skip the decrement on the very frame stun started. Without this, a
	# short blockstun (e.g. a plus-on-block poke) could have its timer set
	# in take_hit() and then immediately decremented past zero in this same
	# physics tick — because take_hit() can be called from the *attacker's*
	# _physics_process earlier in the same frame — ending BLOCKSTUN before
	# the block_idle/crouch_block_idle animation ever got a chance to be
	# seen, making it look like the block reaction never played.
	if stun_just_started:
		stun_just_started = false
	else:
		stun_timer -= delta

	if stun_timer <= 0.0:
		_dbg("[BLOCKSTUN] timer expired")
		state = State.NEUTRAL
		block_idle_sprite.visible = false
		crouch_block_idle_sprite.visible = false

		# take_hit() clears crouch_phase to NONE so the block-idle sprite can
		# take over cleanly, but that means the player LOOKS like they never
		# stood up. If they're still holding Down when blockstun ends, drop
		# straight back into the crouch loop instead of letting
		# _handle_crouch_input() treat this as a brand-new crouch press
		# (which would play the full crouch_down "stand up then crouch
		# again" transition even though the player was crouching the whole
		# time).
		if is_blocking_low and is_on_floor() and Input.is_action_pressed("DownP1"):
			_dbg("[BLOCKSTUN] Down still held after crouch-block -> staying crouched, skipping crouch_down transition")
			wants_to_crouch = true
			crouch_phase = CrouchPhase.LOOP
			_play_anim("crouch_idle", crouch_sprite, true)
		else:
			_update_animation(false)


func _knockdown_process(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()


# ── Minimum visible stun duration ────────────────────────────────
# A move can be plus enough on block/hit that the calculated stun is only
# a couple of frames — shorter than the reaction animation itself. In that
# case BLOCKSTUN/HITSTUN would end (and _update_animation would switch back
# to idle/walk) before the block/hit animation ever finished even one
# playthrough, which looks like it "didn't play" even though it briefly
# did. This floors the stun to however many frames the relevant animation
# actually needs, so the reaction is always fully visible. Gameplay-wise
# this only ever adds frames, never removes stun the move data specified.
func _min_visible_stun_frames(anim_name: String) -> int:
	if not animation_player.has_animation(anim_name):
		return 0
	return int(ceil(animation_player.get_animation(anim_name).length * 60.0))


# ── When the player is hit ───────────────────────────────────────
func take_hit(move_data: MoveData, _attacker) -> bool:
	var was_crouching = (crouch_phase != CrouchPhase.NONE)
	_dbg("[TAKE HIT] was_crouching=%s incoming move='%s'" % [was_crouching, move_data.move_name])

	crouch_phase = CrouchPhase.NONE
	wants_to_crouch = false

	var block_ready = _is_block_ready()
	if block_ready:
		state = State.BLOCKSTUN
		is_blocking_low = was_crouching
		var stun_frames = move_data.recovery + move_data.block_advantage
		if stun_frames < 0:
			stun_frames = 0

		var reaction_anim := "crouch_block_idle" if is_blocking_low else "block_idle"
		var min_frames := _min_visible_stun_frames(reaction_anim)
		if stun_frames < min_frames:
			_dbg("[TAKE HIT] stun_frames=%d shorter than '%s' (%d frames) -> flooring to %d" % [stun_frames, reaction_anim, min_frames, min_frames])
			stun_frames = min_frames

		stun_timer = stun_frames / 60.0
		stun_just_started = true

		_dbg("[TAKE HIT] BLOCKED! stun_frames=%d stun_timer=%.4f is_blocking_low=%s" % [stun_frames, stun_timer, is_blocking_low])

		# Deferred: take_hit() can be called from inside an Area2D
		# area_entered signal (e.g. a signal-based hit detector), which
		# fires while the physics engine is mid-flush of its collision
		# queries. _play_anim() plays/stops animations that include tracks
		# toggling hitbox/hurtbox "disabled" flags, and touching an Area2D's
		# monitoring state during that flush throws
		# "Can't change this state while flushing queries." Deferring
		# pushes the actual animation/sprite work to right after the
		# physics step finishes, which is safe.
		call_deferred("_apply_block_reaction_visuals")

		return true
	else:
		state = State.HITSTUN
		var hitstun_frames = move_data.hitstun

		var reaction_anim := "crouch_hit" if was_crouching else "mid_hit"
		var min_frames := _min_visible_stun_frames(reaction_anim)
		if hitstun_frames < min_frames:
			_dbg("[TAKE HIT] hitstun_frames=%d shorter than '%s' (%d frames) -> flooring to %d" % [hitstun_frames, reaction_anim, min_frames, min_frames])
			hitstun_frames = min_frames

		stun_timer = hitstun_frames / 60.0
		stun_just_started = true
		_dbg("[TAKE HIT] HIT (not blocked)! hitstun_frames=%d stun_timer=%.4f was_crouching=%s" % [hitstun_frames, stun_timer, was_crouching])

		# See comment above — deferred for the same physics-query-flush reason.
		call_deferred("_apply_hit_reaction_visuals", was_crouching)

		return false


func _apply_block_reaction_visuals() -> void:
	_hide_all_sprites()
	if is_blocking_low:
		crouch_block_idle_sprite.visible = true
		_play_anim("crouch_block_idle", crouch_block_idle_sprite, true)
	else:
		block_idle_sprite.visible = true
		_play_anim("block_idle", block_idle_sprite, true)


func _apply_hit_reaction_visuals(was_crouching: bool) -> void:
	_hide_all_sprites()
	if was_crouching:
		crouch_hit_sprite.visible = true
		_play_anim("crouch_hit", crouch_hit_sprite, true)
	else:
		mid_hit_sprite.visible = true
		_play_anim("mid_hit", mid_hit_sprite, true)


# ── Gravity / Jump / Crouch / Movement ───────────────────────────
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += GRAVITY * delta


func _handle_jump() -> void:
	if not is_on_floor() or crouch_phase != CrouchPhase.NONE:
		return
	if not Input.is_action_just_pressed("JumpP1"):
		return
	velocity.y = JUMP_VELOCITY
	air_horizontal_velocity = _get_horizontal_input() * _current_walk_speed()
	is_landing = false
	_dbg("[JUMP] launched with air_horizontal_velocity=%.1f" % air_horizontal_velocity)


func _handle_crouch_input() -> void:
	var down_pressed = is_on_floor() and Input.is_action_pressed("DownP1")

	# Only act on state transitions
	if down_pressed and crouch_phase == CrouchPhase.NONE:
		wants_to_crouch = true
		crouch_phase = CrouchPhase.TRANSITION_DOWN
		_dbg("[CROUCH] DOWN pressed -> TRANSITION_DOWN, playing crouch_down")
		_play_anim("crouch_down", crouch_sprite, true)  # force restart
	elif not down_pressed and crouch_phase == CrouchPhase.LOOP:
		wants_to_crouch = false
		crouch_phase = CrouchPhase.STAND_UP
		_dbg("[CROUCH] DOWN released from LOOP -> STAND_UP, playing crouch_up")
		_play_anim("crouch_up", crouch_sprite, true)    # force restart
	elif not down_pressed and crouch_phase == CrouchPhase.TRANSITION_DOWN and wants_to_crouch:
		wants_to_crouch = false
		_dbg("[CROUCH] DOWN released mid-TRANSITION_DOWN -> will stand up once crouch_down finishes")
	elif down_pressed and crouch_phase == CrouchPhase.TRANSITION_DOWN and not wants_to_crouch:
		# Re-pressed Down again before crouch_down even finished
		wants_to_crouch = true
		_dbg("[CROUCH] DOWN re-pressed mid-TRANSITION_DOWN -> will crouch once crouch_down finishes")


func _handle_horizontal_movement(delta: float) -> void:
	if not is_on_floor():
		if pushback_velocity_x != 0.0:
			pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, PUSHBACK_DECELERATION * delta)
			air_horizontal_velocity = pushback_velocity_x
		velocity.x = air_horizontal_velocity
		return
	if crouch_phase != CrouchPhase.NONE:
		velocity.x = 0.0
		return
	if is_landing:
		velocity.x = _get_horizontal_input() * _current_walk_speed()
		return

	if pushback_velocity_x != 0.0:
		pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, PUSHBACK_DECELERATION * delta)
		velocity.x = pushback_velocity_x
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


# ── Animation selection ──────────────────────────────────────────
func _update_animation(just_landed: bool = false) -> void:
	# Let the landing animation finish first
	if is_landing and not just_landed:
		return

	# Crouch transitions handled by _on_animation_finished, don't interrupt
	if crouch_phase != CrouchPhase.NONE:
		return

	if not is_on_floor():
		var phase = _get_jump_phase()
		match phase:
			JumpPhase.RISE:
				_play_anim("jump_rise", jump_sprite)
			JumpPhase.PEAK:
				_play_anim("jump_peak", jump_sprite)
			JumpPhase.FALL:
				if current_anim != "jump_peak":
					_dbg("[JUMP FALL] entering FALL from '%s' -> snapping to held last frame" % current_anim)
					_play_anim("jump_peak", jump_sprite, true)
					var anim2 = animation_player.get_animation("jump_peak")
					animation_player.seek(anim2.length - 0.001, true)
					animation_player.pause()
				elif animation_player.is_playing():
					_dbg("[JUMP FALL] jump_peak mid-playback, skipping ahead to held last frame")
					var anim = animation_player.get_animation("jump_peak")
					animation_player.seek(anim.length - 0.001, true)
					animation_player.pause()
	else:
		if is_landing:
			return
		var direction := _get_horizontal_input()
		if direction == 0.0:
			_play_anim("idle", idle_sprite)
			last_direction = Direction.NONE
		else:
			if direction > 0.0:
				_play_anim("walk_forward", walk_forward_sprite)
			else:
				_play_anim("walk_backward", walk_backward_sprite)


func _get_jump_phase() -> JumpPhase:
	if velocity.y < -JUMP_APEX_THRESHOLD:
		return JumpPhase.RISE
	if velocity.y > JUMP_APEX_THRESHOLD:
		return JumpPhase.FALL
	return JumpPhase.PEAK


# ── Animation finished callback ──────────────────────────────────
func _on_animation_finished(anim_name: String) -> void:
	_dbg("[ANIM FINISHED] '%s' | crouch_phase=%s wants_to_crouch=%s" % [
		anim_name, CrouchPhase.keys()[crouch_phase], wants_to_crouch
	])

	# Pause on the last frame for all hold-on-finish animations
	if anim_name in HOLD_ON_FINISH_ANIMS:
		animation_player.pause()

	match anim_name:
		"jump_land":
			is_landing = false
			_update_animation(false)

		"crouch_down":
			if wants_to_crouch:
				crouch_phase = CrouchPhase.LOOP
				_dbg("[CROUCH] crouch_down finished, still wanted -> LOOP, playing crouch_idle")
				_play_anim("crouch_idle", crouch_sprite, true)
			else:
				# Changed mind mid-animation (Down was released before crouch_down finished)
				crouch_phase = CrouchPhase.STAND_UP
				_dbg("[CROUCH] crouch_down finished, cancelled -> STAND_UP, playing crouch_up")
				_play_anim("crouch_up", crouch_sprite, true)

		"crouch_up":
			crouch_phase = CrouchPhase.NONE
			wants_to_crouch = false
			_dbg("[CROUCH] crouch_up finished -> NONE")
			_update_animation(false)


# ── Animation Event Freeze Pattern ────────────────────────────────
func freeze_until_landing() -> void:
	_dbg("[FREEZE] jump_peak reached its hold frame -> pausing, awaiting 'landed'")
	animation_player.pause()
	await landed
	_dbg("[FREEZE] 'landed' received -> resuming jump_peak")
	if animation_player.current_animation == "jump_peak":
		animation_player.play()

func freeze_until_hitstun_recovery() -> void:
	_dbg("[FREEZE] hit-reaction (%s) reached its hold frame -> pausing, awaiting 'hitstun_finished'" % current_anim)
	animation_player.pause()
	await hitstun_finished
	_dbg("[FREEZE] 'hitstun_finished' received -> resuming %s" % current_anim)
	if current_anim in ["crouch_hit", "mid_hit"]:
		animation_player.play()


# ── Utility: play an animation and show the correct sprite ──────
func _play_anim(anim_name: String, sprite_to_show: Sprite2D = null, force_restart: bool = false) -> void:
	if not animation_player.has_animation(anim_name):
		push_error("Animation not found: '%s'" % anim_name)
		return

	# If already on this animation and it's a hold-on-finish, never restart
	if not force_restart and current_anim == anim_name:
		if anim_name in HOLD_ON_FINISH_ANIMS:
			return  # Always skip — already showing the right thing
		# For looping animations, only skip if actively playing
		if animation_player.is_playing():
			return

	var anim_res := animation_player.get_animation(anim_name)
	_dbg("[PLAY ANIM] '%s' (was '%s') force_restart=%s loop_mode=%s length=%.4f" % [
		anim_name, current_anim, force_restart,
		anim_res.loop_mode if anim_res else "N/A",
		anim_res.length if anim_res else -1.0
	])

	# Stop and hide everything first
	animation_player.stop()
	_hide_all_sprites()

	# Show the correct sprite if provided
	if sprite_to_show:
		sprite_to_show.visible = true

	current_anim = anim_name
	animation_player.play(anim_name)
	animation_player.seek(0.0, true)  # force immediate apply — without this, the sprite
									   # shows the PREVIOUS animation's last frame for one
									   # tick before snapping to the new one (the flicker)
	if sprite_to_show == crouch_sprite:
		_dbg("[PLAY ANIM] after seek: Crouch.frame=%d" % crouch_sprite.frame)


func _hide_all_sprites() -> void:
	idle_sprite.visible = false
	walk_backward_sprite.visible = false
	walk_forward_sprite.visible = false
	jump_sprite.visible = false
	crouch_sprite.visible = false
	_hide_attack_sprites()
	block_idle_sprite.visible = false
	crouch_block_idle_sprite.visible = false
	mid_block_warning.visible = false
	low_block_warning.visible = false
	crouch_hit_sprite.visible = false
	mid_hit_sprite.visible = false

func _hide_attack_sprites() -> void:
	n5_sprite.visible = false
	n52_sprite.visible = false
	s5_sprite.visible = false
	na_sprite.visible = false


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
	$Hurtbox/MainHurtbox.position = new_pos
