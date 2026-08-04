extends CharacterBody2D
class_name Player

# ── Multiplayer ──────────────────────────────────────────────────
# player_id determines both input mapping ("LeftP1" vs "LeftP2") and
# facing. Player 1 always faces right, Player 2 always faces left —
# fixed at _ready(), never recalculated during play.
@export_group("Multiplayer")
@export var player_id: int = 1

# ── Movement ─────────────────────────────────────────────────────
@export_group("Movement")
@export var walk_forward_speed: float = 170.0
@export var walk_backward_speed: float = 170.0
@export var jump_velocity: float = -550.0
@export var gravity: float = 1180.0
@export var jump_apex_threshold: float = 60.0

# ── Pushback ─────────────────────────────────────────────────────
@export_group("Pushback")
@export var pushback_deceleration: float = 600.0

# ── Hurtbox ──────────────────────────────────────────────────────
@export_group("Hurtbox")
@export var hurtbox_vertical_reduction: float = 80.0

# ── Combat timing ────────────────────────────────────────────────
@export_group("Combat Timing")
@export var gatling_buffer_frames: int = 16
@export var direction_buffer_time: float = 0.1

# ── Debug ────────────────────────────────────────────────────────
@export_group("Debug")
@export var debug: bool = true

# ── States ──────────────────────────────────────────────────────
enum State { NEUTRAL, ATTACK, HITSTUN, BLOCKSTUN, KNOCKDOWN }
enum JumpPhase { RISE, PEAK, FALL }
enum Direction { NONE, LEFT, RIGHT }
enum CrouchPhase { NONE, TRANSITION_DOWN, LOOP, STAND_UP }

# Fixed at _ready() from player_id — P1 = true (faces right), P2 = false.
var facing_right: bool = true
var state: State = State.NEUTRAL :
	set(new_state):
		if state != new_state:
			_dbg("[STATE] %s -> %s" % [State.keys()[state], State.keys()[new_state]])
			state = new_state
			EventBus.player_state[player_id] = state
			EventBus.player_state_changed.emit(player_id, state)

signal landed
signal hitstun_finished

var air_horizontal_velocity: float = 0.0

var last_direction: int = Direction.NONE
var direction_buffer_timer: float = 0.0
var pending_direction: int = Direction.NONE

# ── Attack state ────────────────────────────────────────────────
@export_group("Moves")
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

var pushback_velocity_x: float = 0.0
var has_used_aerial: bool = false

var stun_timer: float = 0.0
var stun_just_started: bool = false

var is_blocking_low: bool = false

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprites: PlayerVisuals = $Sprites
@onready var camera: Camera2D = get_viewport().get_camera_2d()
@onready var hurtbox_shape: RectangleShape2D = $Hurtbox/MainHurtbox.shape
@onready var hitbox_shape: RectangleShape2D = $Hitbox/MainHitbox.shape
var base_hurtbox_size: Vector2
var base_hurtbox_position: Vector2

var is_landing: bool = false
var crouch_phase: int = CrouchPhase.NONE :
	set(new_phase):
		if crouch_phase != new_phase:
			_dbg("[CROUCH PHASE] %s -> %s" % [CrouchPhase.keys()[crouch_phase], CrouchPhase.keys()[new_phase]])
		crouch_phase = new_phase
		EventBus.player_crouching[player_id] = (new_phase != CrouchPhase.NONE)

var wants_to_crouch: bool = false


func _dbg(msg: String) -> void:
	if debug:
		print("[P%d] %s" % [player_id, msg])


# Builds "LeftP1"/"LeftP2" etc. from player_id, so every input check
# routes through here instead of a hardcoded "...P1" literal.
func _action(name: String) -> StringName:
	return StringName("%sP%d" % [name, player_id])


func _ready() -> void:
	# Fixed facing: P1 faces right, everyone else faces left. Not live —
	# set once and never recalculated.
	facing_right = (player_id == 1)
	_dbg("[SETUP] player_id=%d facing_right=%s groups=%s" % [player_id, facing_right, get_groups()])

	# Hitbox/Hurtbox positions are driven per-frame by AnimationPlayer
	# keyframes authored assuming "always faces right." Rather than
	# mirroring each keyframe (which would just get overwritten by the
	# animation on the next play anyway), flip the parent Area2D's scale —
	# every local position the animation sets on MainHitbox/MainHurtbox
	# gets mirrored into world space automatically, every frame, with no
	# keyframe edits needed.
	if not facing_right:
		$Hitbox.scale.x = -1.0
		$Hurtbox.scale.x = -1.0
		_dbg("[SETUP] mirrored Hitbox/Hurtbox via scale.x = -1")

	# Shape resources embedded in the scene are shared across every
	# instance unless duplicated — without this, one player's attack
	# animation resizing/moving MainHitbox's (or MainHurtbox's) shape
	# also mutates the other player's, since they'd be the same
	# Resource object under the hood.
	$Hurtbox/MainHurtbox.shape = hurtbox_shape.duplicate()
	hurtbox_shape = $Hurtbox/MainHurtbox.shape
	$Hitbox/MainHitbox.shape = hitbox_shape.duplicate()
	hitbox_shape = $Hitbox/MainHitbox.shape

	base_hurtbox_size = hurtbox_shape.size
	base_hurtbox_position = $Hurtbox/MainHurtbox.position

	# Move lookup has to exist before sprites.setup(), since PlayerVisuals
	# builds its attack-sprite dictionary from all_moves.keys() — only
	# wiring up sprites for moves that are actually assigned.
	_build_move_lookup()

	sprites.setup(animation_player, all_moves.keys())
	sprites.set_facing(facing_right)
	sprites.animation_finished.connect(_on_sprites_animation_finished)

	var players = get_tree().get_nodes_in_group("players")
	_dbg("[SETUP] 'players' group has %d node(s): %s" % [players.size(), players.map(func(p): return p.name)])
	for p in players:
		# Only match actual Player instances — anything else sharing the
		# "players" group (dummies, testers, etc.) should not be picked
		# up as an opponent.
		if p != self and p is Player:
			opponent = p
			_dbg("[SETUP] Opponent found: %s (player_id=%d)" % [opponent.name, opponent.player_id])
			break
	if not opponent:
		push_warning("[SETUP] No opponent found in 'players' group! Check this node is in the group in the editor's Node > Groups tab, and that it's a Player instance.")

	sprites.play_idle()


func _build_move_lookup() -> void:
	var _add_move = func(move: MoveData, dict: Dictionary, key: String):
		if move:
			all_moves[move.move_name] = move
			dict[key] = move

	_add_move.call(N5, normal_moves, "neutral")
	_add_move.call(N4, normal_moves, "back")
	_add_move.call(N6, normal_moves, "forward")
	_add_move.call(N2, normal_moves, "crouching")
	_add_move.call(N8, normal_moves, "up")
	_add_move.call(NA, normal_moves, "aerial")
	_add_move.call(N52, normal_moves, "")

	_add_move.call(S5, special_moves, "neutral")
	_add_move.call(S4, special_moves, "back")
	_add_move.call(S6, special_moves, "forward")
	_add_move.call(S2, special_moves, "crouching")
	_add_move.call(S8, special_moves, "up")
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

	EventBus.player_position[player_id] = global_position
	EventBus.player_velocity[player_id] = velocity
	EventBus.player_is_airborne[player_id] = not is_on_floor()


# ── Neutral state ────────────────────────────────────────────────
func _neutral_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	_apply_gravity(delta)
	_handle_jump()
	_handle_crouch_input()
	_handle_horizontal_movement(delta)
	move_and_slide()
	_clamp_to_camera_bounds()
	var just_landed := is_on_floor() and not was_on_floor

	if just_landed:
		has_used_aerial = false
		is_landing = true
		_dbg("[LANDED] emitting landed signal")
		landed.emit()
		sprites.play_jump_land()

	_update_animation(just_landed)
	_update_hurtbox()
	sprites.update_block_warning(delta, _is_block_ready(), crouch_phase != CrouchPhase.NONE)

	if Input.is_action_just_pressed(_action("Normal")):
		var move = _resolve_move("normal")
		if move:
			_start_attack(move)

	if Input.is_action_just_pressed(_action("Special")):
		var move = _resolve_move("special")
		if move:
			_start_attack(move)


# "Backward" is relative to facing, not a fixed world direction — for
# P1 (faces right) backward is Left, for P2 (faces left) backward is
# Right. Same pattern as the walk-animation forward/backward fix.
func _get_backward_action() -> StringName:
	return _action("Left") if facing_right else _action("Right")


func _is_block_ready() -> bool:
	if not is_on_floor():
		return false
	var backward_held = Input.is_action_pressed(_get_backward_action())
	if not backward_held:
		return false
	if crouch_phase != CrouchPhase.NONE:
		return Input.is_action_pressed(_action("Down"))
	return true


# _is_block_ready() only checks "is the player holding the block input
# correctly" — it says nothing about whether that posture actually stops
# THIS move. That check was missing entirely, which is why OVERHEAD moves
# never beat crouch-block (and LOW moves never beat standing block) —
# every blocked hit was treated as a successful block regardless of
# hit_level. This is that missing check:
#   - OVERHEAD must be blocked standing (crouch-block does not stop it)
#   - LOW must be blocked crouching (standing block does not stop it)
#   - MID is blocked by either posture
func _block_posture_beats_hit_level(hit_level: MoveData.HitLevel, was_crouching: bool) -> bool:
	match hit_level:
		MoveData.HitLevel.OVERHEAD:
			if was_crouching:
				_dbg("[BLOCK] OVERHEAD move beats crouch-block")
			return not was_crouching
		MoveData.HitLevel.LOW:
			if not was_crouching:
				_dbg("[BLOCK] LOW move beats standing block")
			return was_crouching
		_: # MID
			return true


# ── Attack resolve / start ───────────────────────────────────────
# Move keys: "neutral" / "forward" / "back" / "crouching" / "up" / "aerial".
# "up" is a grounded input (Up + Normal/Special, e.g. N8/S8) — distinct
# from the Jump action. It's also reused as the airborne fallback attack
# when no dedicated "aerial" move is set, since that's the classic
# fighting-game "jumping normal" behavior.
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
		key = "up"
	elif crouch_phase == CrouchPhase.LOOP:
		key = "crouching"
	elif Input.is_action_pressed(_action("Up")):
		key = "up"
	else:
		var dir = _get_horizontal_input()
		if dir == 0.0:
			key = "neutral"
		elif (dir > 0.0) == facing_right:
			key = "forward"
		else:
			key = "back"

	var move = dict.get(key, null)
	if move == null and key != "neutral" and key != "crouching" and key != "up":
		move = dict.get("neutral", null)
	return move


func _start_attack(move: MoveData) -> void:
	if not move:
		return

	_dbg("[ATTACK] starting move '%s' facing_right=%s" % [move.move_name, facing_right])

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

	sprites.hide_all_sprites()
	sprites.reset_block_warning()
	sprites.show_attack_sprite(move.move_name)

	EventBus.player_attack_started.emit(player_id, move.move_name)

	sprites.play_attack_anim(move.animation_name)


# ── Attack process ───────────────────────────────────────────────
func _attack_process(delta: float) -> void:
	var move_velocity := velocity

	if not is_on_floor() and current_move:
		move_velocity.y *= 0.85
		move_velocity.y += gravity * delta * 0.6
	else:
		move_velocity.y = 0.0

	if current_move and current_move.is_advancing and pushback_velocity_x == 0.0:
		if attack_frame == 1:
			# Advance in the direction this player actually faces, not
			# always world-right.
			move_velocity.x = current_move.advance_speed * (1.0 if facing_right else -1.0)
		else:
			move_velocity.x = move_velocity.x * 0.85

	if pushback_velocity_x != 0.0:
		move_velocity.x = pushback_velocity_x
		pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, pushback_deceleration * delta)

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
	if Input.is_action_just_pressed(_action("Normal")):
		gatling_input_buffered = _action("Normal")
		gatling_buffer_timer = gatling_buffer_frames

	if gatling_input_buffered != "":
		gatling_buffer_timer -= 1
		if gatling_buffer_timer <= 0:
			gatling_input_buffered = ""
			gatling_buffer_timer = 0
			return

	if gatling_input_buffered == _action("Normal") and current_move.gatlings_into.size() > 0:
		var gatling_name = current_move.gatlings_into[0]
		if all_moves.has(gatling_name):
			_dbg("[GATLING] buffered input confirmed -> canceling into '%s'" % gatling_name)
			_start_attack(all_moves[gatling_name])


func _end_attack() -> void:
	var was_airborne := not is_on_floor()
	_dbg("[END ATTACK] current_anim was '%s' | was_airborne=%s velocity.y=%.1f" % [sprites.get_current_anim(), was_airborne, velocity.y])

	state = State.NEUTRAL
	attack_frame = 0
	current_move = null
	gatling_input_buffered = ""
	gatling_buffer_timer = 0

	if was_airborne:
		air_horizontal_velocity = velocity.x

	sprites.hide_attack_sprites()
	_update_animation(false)


func _check_hit() -> void:
	if not opponent:
		_dbg("[CHECK HIT] no opponent set — skipping (this is why nothing ever connects)")
		return

	var hitbox = $Hitbox
	var hitbox_area_shape = hitbox.get_node("MainHitbox")
	if hitbox_area_shape.disabled:
		_dbg("[CHECK HIT] MainHitbox is disabled this frame — skipping")
		return

	var overlapping = hitbox.get_overlapping_areas()
	_dbg("[CHECK HIT] frame=%d hitbox.global_position=%s overlapping_areas=%s" % [
		attack_frame, hitbox_area_shape.global_position, overlapping.map(func(a): return a.get_path())
	])

	if overlapping.is_empty():
		return

	var opponent_hurtbox = opponent.get_node("Hurtbox")
	for area in overlapping:
		if area == opponent_hurtbox or area.get_parent() == opponent_hurtbox:
			var was_blocked = opponent.take_hit(current_move, self)
			hit_connected = true
			_dbg("[HIT] '%s' connected on opponent | blocked=%s" % [current_move.move_name, was_blocked])
			EventBus.player_hit_landed.emit(player_id, current_move.move_name, was_blocked)
			EventBus.hit_confirmed.emit(hitbox_area_shape.global_position, current_move, self, opponent, was_blocked)
			if was_blocked:
				_apply_pushback()
			return

	_dbg("[CHECK HIT] overlaps found but none matched opponent's Hurtbox (expected %s)" % opponent_hurtbox.get_path())


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

	if stun_just_started:
		stun_just_started = false
	else:
		stun_timer -= delta

	if stun_timer <= 0.0:
		_dbg("[HITSTUN] timer expired -> emitting hitstun_finished")
		state = State.NEUTRAL
		hitstun_finished.emit()
		_update_animation(false)


func _blockstun_process(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	if is_blocking_low:
		sprites.play_block_idle(true)
		EventBus.player_blocking_low[player_id] = true
	else:
		sprites.play_block_idle(false)
		EventBus.player_blocking_low[player_id] = false

	if stun_just_started:
		stun_just_started = false
	else:
		stun_timer -= delta

	if stun_timer <= 0.0:
		_dbg("[BLOCKSTUN] timer expired")
		state = State.NEUTRAL
		sprites.hide_block_sprites()

		if is_blocking_low and is_on_floor() and Input.is_action_pressed(_action("Down")):
			_dbg("[BLOCKSTUN] Down still held after crouch-block -> staying crouched, skipping crouch_down transition")
			wants_to_crouch = true
			crouch_phase = CrouchPhase.LOOP
			sprites.play_crouch_idle()
		else:
			_update_animation(false)


func _knockdown_process(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()


# Warns (once per move, not once per hit) if a move has been tuned with
# a tag that has no gameplay implementation yet, so a designer setting
# knock_back/launcher_strength on a MoveData resource gets told "this
# won't do anything" instead of silently wondering why nothing happens.
var _warned_unimplemented_moves: Dictionary = {}

func _warn_unimplemented_tags(move_data: MoveData) -> void:
	if _warned_unimplemented_moves.has(move_data.move_name):
		return

	var messages: Array[String] = []
	if move_data.knock_back != 0.0:
		messages.append("knock_back=%.1f" % move_data.knock_back)
	if move_data.block_knock_back != 0.0:
		messages.append("block_knock_back=%.1f" % move_data.block_knock_back)
	if move_data.is_launcher:
		messages.append("is_launcher=true (launcher_strength=%.1f)" % move_data.launcher_strength)

	if not messages.is_empty():
		_warned_unimplemented_moves[move_data.move_name] = true
		push_warning("[MoveData] '%s' has %s set, but this tag is not implemented yet in take_hit()/_apply_pushback() — it currently has no gameplay effect." % [
			move_data.move_name, ", ".join(messages)
		])


func _min_visible_stun_frames(anim_name: String) -> int:
	if not animation_player.has_animation(anim_name):
		return 0
	return int(ceil(animation_player.get_animation(anim_name).length * 60.0))


func take_hit(move_data: MoveData, _attacker) -> bool:
	var was_crouching = (crouch_phase != CrouchPhase.NONE)
	_dbg("[TAKE HIT] was_crouching=%s incoming move='%s' hit_level=%s" % [
		was_crouching, move_data.move_name, MoveData.HitLevel.keys()[move_data.hit_level]
	])

	crouch_phase = CrouchPhase.NONE
	wants_to_crouch = false

	_warn_unimplemented_tags(move_data)

	var block_ready = _is_block_ready() and _block_posture_beats_hit_level(move_data.hit_level, was_crouching)
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

		call_deferred("_apply_hit_reaction_visuals", was_crouching)

		return false


func _apply_block_reaction_visuals() -> void:
	sprites.play_block_idle(is_blocking_low, true)


func _apply_hit_reaction_visuals(was_crouching: bool) -> void:
	sprites.play_hit_reaction(was_crouching)


# ── Gravity / Jump / Crouch / Movement ───────────────────────────
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += gravity * delta


func _handle_jump() -> void:
	if not is_on_floor() or crouch_phase != CrouchPhase.NONE:
		return
	if not Input.is_action_just_pressed(_action("Jump")):
		return
	velocity.y = jump_velocity
	air_horizontal_velocity = _get_horizontal_input() * _current_walk_speed()
	is_landing = false
	_dbg("[JUMP] launched with air_horizontal_velocity=%.1f" % air_horizontal_velocity)


func _handle_crouch_input() -> void:
	var down_pressed = is_on_floor() and Input.is_action_pressed(_action("Down"))

	if down_pressed and crouch_phase == CrouchPhase.NONE:
		wants_to_crouch = true
		crouch_phase = CrouchPhase.TRANSITION_DOWN
		_dbg("[CROUCH] DOWN pressed -> TRANSITION_DOWN, playing crouch_down")
		sprites.play_crouch_down()
	elif not down_pressed and crouch_phase == CrouchPhase.LOOP:
		wants_to_crouch = false
		crouch_phase = CrouchPhase.STAND_UP
		_dbg("[CROUCH] DOWN released from LOOP -> STAND_UP, playing crouch_up")
		sprites.play_crouch_up()
	elif not down_pressed and crouch_phase == CrouchPhase.TRANSITION_DOWN and wants_to_crouch:
		wants_to_crouch = false
		_dbg("[CROUCH] DOWN released mid-TRANSITION_DOWN -> will stand up once crouch_down finishes")
	elif down_pressed and crouch_phase == CrouchPhase.TRANSITION_DOWN and not wants_to_crouch:
		wants_to_crouch = true
		_dbg("[CROUCH] DOWN re-pressed mid-TRANSITION_DOWN -> will crouch once crouch_down finishes")


func _handle_horizontal_movement(delta: float) -> void:
	if not is_on_floor():
		if pushback_velocity_x != 0.0:
			pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, pushback_deceleration * delta)
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
		pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, pushback_deceleration * delta)
		velocity.x = pushback_velocity_x
		return

	var raw_direction := _get_raw_direction()
	if raw_direction != last_direction and raw_direction != Direction.NONE:
		pending_direction = raw_direction
		direction_buffer_timer = direction_buffer_time
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
	if Input.is_action_pressed(_action("Left")):
		return Direction.LEFT
	elif Input.is_action_pressed(_action("Right")):
		return Direction.RIGHT
	return Direction.NONE

func _direction_to_float(dir: int) -> float:
	match dir:
		Direction.LEFT: return -1.0
		Direction.RIGHT: return 1.0
	return 0.0

func _get_horizontal_input() -> float:
	var dir := 0.0
	if Input.is_action_pressed(_action("Left")): dir -= 1.0
	if Input.is_action_pressed(_action("Right")): dir += 1.0
	return dir

func _current_walk_speed() -> float:
	return walk_backward_speed if _get_horizontal_input() < 0.0 else walk_forward_speed

func _speed_for_direction(dir: int) -> float:
	return walk_backward_speed if dir == Direction.LEFT else walk_forward_speed


# ── Animation selection ──────────────────────────────────────────
# NOTE: "walk_forward" / "walk_backward" are relative to which way this
# player is FACING, not raw world direction. For P1 (faces right) those
# happen to be the same thing, which is why this bug was invisible until
# P2 (faces left) started walking right (backward) and got the forward
# animation instead.
func _update_animation(just_landed: bool = false) -> void:
	if is_landing and not just_landed:
		return

	if crouch_phase != CrouchPhase.NONE:
		return

	if not is_on_floor():
		var phase = _get_jump_phase()
		match phase:
			JumpPhase.RISE:
				sprites.play_jump_rise()
			JumpPhase.PEAK:
				sprites.play_jump_peak()
			JumpPhase.FALL:
				sprites.play_jump_fall()
	else:
		if is_landing:
			return
		var direction := _get_horizontal_input()
		if direction == 0.0:
			sprites.play_idle()
			last_direction = Direction.NONE
		else:
			var moving_right := direction > 0.0
			var is_forward := (moving_right == facing_right)
			sprites.play_walk(is_forward)


func _get_jump_phase() -> JumpPhase:
	if velocity.y < -jump_apex_threshold:
		return JumpPhase.RISE
	if velocity.y > jump_apex_threshold:
		return JumpPhase.FALL
	return JumpPhase.PEAK


func _on_sprites_animation_finished(anim_name: String) -> void:
	_dbg("[ANIM FINISHED] '%s' | crouch_phase=%s wants_to_crouch=%s" % [
		anim_name, CrouchPhase.keys()[crouch_phase], wants_to_crouch
	])

	match anim_name:
		"jump_land":
			is_landing = false
			_update_animation(false)

		"crouch_down":
			if wants_to_crouch:
				crouch_phase = CrouchPhase.LOOP
				_dbg("[CROUCH] crouch_down finished, still wanted -> LOOP, playing crouch_idle")
				sprites.play_crouch_idle()
			else:
				crouch_phase = CrouchPhase.STAND_UP
				_dbg("[CROUCH] crouch_down finished, cancelled -> STAND_UP, playing crouch_up")
				sprites.play_crouch_up()

		"crouch_up":
			crouch_phase = CrouchPhase.NONE
			wants_to_crouch = false
			_dbg("[CROUCH] crouch_up finished -> NONE")
			_update_animation(false)


func freeze_until_landing() -> void:
	_dbg("[FREEZE] jump_peak reached its hold frame -> pausing, awaiting 'landed'")
	animation_player.pause()
	await landed
	_dbg("[FREEZE] 'landed' received -> resuming jump_peak")
	if animation_player.current_animation == "jump_peak":
		animation_player.play()

func freeze_until_hitstun_recovery() -> void:
	_dbg("[FREEZE] hit-reaction (%s) reached its hold frame -> pausing, awaiting 'hitstun_finished'" % sprites.get_current_anim())
	animation_player.pause()
	await hitstun_finished
	_dbg("[FREEZE] 'hitstun_finished' received -> resuming %s" % sprites.get_current_anim())
	if sprites.get_current_anim() in ["crouch_hit", "mid_hit"]:
		animation_player.play()


func _update_hurtbox() -> void:
	var new_size := base_hurtbox_size
	var new_pos := base_hurtbox_position
	var reduction := hurtbox_vertical_reduction

	if not is_on_floor():
		new_size.y = base_hurtbox_size.y - reduction
		new_pos.y = base_hurtbox_position.y - reduction * 0.5
	elif crouch_phase != CrouchPhase.NONE:
		new_size.y = base_hurtbox_size.y - reduction
		new_pos.y = base_hurtbox_position.y + reduction * 0.5

	hurtbox_shape.size = new_size
	$Hurtbox/MainHurtbox.position = new_pos

func _clamp_to_camera_bounds():
	if not camera:
		return

	var left_limit = camera.global_position.x - (get_viewport_rect().size.x / (2 * camera.zoom.x))
	var right_limit = camera.global_position.x + (get_viewport_rect().size.x / (2 * camera.zoom.x))

	var padding = 40.0

	global_position.x = clamp(
		global_position.x,
		left_limit + padding,
		right_limit - padding
	)
