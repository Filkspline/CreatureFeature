extends CharacterBody2D
class_name Player

# Determines input mapping ("LeftP1" vs "LeftP2") and starting facing.
# Facing is fixed once at ready and never changes, since this project
# has no cross ups and players never swap sides.
@export_group("Multiplayer")
@export var player_id: int = 1

@export_group("Movement")
@export var walk_forward_speed: float = 170.0
@export var walk_backward_speed: float = 170.0
@export var jump_velocity: float = -720.0
@export var gravity: float = 1600.0
@export var jump_apex_threshold: float = 200.0
##@experimental: Currently used as a stopgap solution for the stat application.
## Just used as the variable that is applied to walk_forward_speed, and
## walk_backward_speed
@export var move_speed: float = 190.0

@export_group("Pushback")
@export var pushback_deceleration: float = 600.0

@export_group("Hurtbox")
@export var hurtbox_vertical_reduction: float = 80.0

@export_group("Combat Timing")
@export var gatling_buffer_frames: int = 26
@export var direction_buffer_time: float = 0.6
@export var knockdown_duration: float = 1.0
## How many physics frames a Jump/Normal/Special press is "remembered"
## for after being pressed. Captured every frame regardless of state,
## so pressing e.g. Jump a few frames before an attack's recovery ends
## still buffers it, and it fires the instant NEUTRAL can act on it
## instead of being silently dropped like a raw is_action_just_pressed
## check would be. Standard fighting-game buffer windows are roughly
## 3-10 frames; keep this on the low end so it doesn't feel laggy.
@export var input_buffer_frames: int = 10

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Visuals")
## Normal draw order, restored any time state leaves ATTACK.
@export var base_z_index: int = 0

@export var attack_z_index: int = 1

@export_group("Debug")
@export var debug: bool = true

@export_group("Upgrades")
## Move names (MoveData.move_name, NOT the slot var name like "S6") that
## start locked — excluded from all_moves/normal_moves/special_moves
## until unlock_move() is called with a MoveData sharing that move_name.
@export var locked_move_names: Array[StringName] = []

enum State { NEUTRAL, ATTACK, HITSTUN, BLOCKSTUN, KNOCKDOWN }
enum JumpPhase { RISE, PEAK, FALL }
enum Direction { NONE, LEFT, RIGHT }
enum CrouchPhase { NONE, TRANSITION_DOWN, LOOP, STAND_UP }

var facing_right: bool = true
var state: State = State.NEUTRAL :
	set(new_state):
		if state == new_state:
			return
		_dbg("[STATE] %s -> %s" % [State.keys()[state], State.keys()[new_state]])
		state = new_state
		EventBus.player_state[player_id] = state
		EventBus.player_state_changed.emit(player_id, state)
		# Overlay whoever is currently attacking on top of their
		# opponent, temporarily. Tied to the state transition itself
		# (not to _start_attack/_end_attack) so a trade — getting hit
		# out of your own attack straight into HITSTUN — still
		# restores z_index correctly, same as a clean attack finish.
		z_index = attack_z_index if new_state == State.ATTACK else base_z_index

signal landed
signal hitstun_finished

var air_horizontal_velocity: float = 0.0

var last_direction: int = Direction.NONE
var direction_buffer_timer: float = 0.0
var pending_direction: int = Direction.NONE

# Generic "remembered" inputs. Keys are the base action names ("Jump",
# "Normal", "Special" — before _action() appends "P1"/"P2"), values are
# frames remaining before the press expires. Captured once per physics
# frame in _capture_buffered_inputs() regardless of current state, and
# consumed via _consume_buffer() wherever that action becomes legal
# again. This is separate from the gatling-cancel buffer below, which
# has its own hit-confirm-gated semantics.
var input_buffer: Dictionary = {}

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
## Jump Aerial — triggered by pressing Jump while already airborne.
## Independent from NA's aerial gate (has_used_aerial): landing NA and
## JA in the same jump is intentional, not a bug. Goes through the
## exact same _start_attack() pipeline as every other move.
@export var JA: MoveData

var all_moves: Dictionary = {}
var normal_moves: Dictionary = {}
var special_moves: Dictionary = {}

var current_move: MoveData = null
var attack_frame: int = 0
# Bumped every _start_attack() call. Lets a Projectile tell "the owner
# swung again" apart from "the owner is still overlapping from the same
# swing", since current_move itself stays the same Resource across
# repeat uses of the same move.
var attack_instance_id: int = 0
# Guards fire_projectile() so a single Call Method track key can't
# spawn more than one projectile per attack, even if seek() ends up
# re-visiting that frame.
var _projectile_fired_this_attack: bool = false
var opponent = null
var hit_connected: bool = false
# Tracks only the current on/off activation of the hitbox, so a move
# whose hitbox toggles disabled -> enabled multiple times in one
# animation (multi-hit NA etc.) can register a fresh hit each time it
# re-enables. hit_connected itself is intentionally NOT reset here,
# since gatling-cancel confirmation (~line 626) needs to know "this
# attack has hit at least once," not "the current window has hit."
var _hit_registered_this_activation: bool = false
var _hitbox_was_disabled_last_frame: bool = true
var gatling_input_buffered: StringName = ""
var gatling_buffer_timer: int = 0
var gatling_cancel_window_open: bool = false

var pushback_velocity_x: float = 0.0
var has_used_aerial: bool = false
## Separate one-shot gate for JA, reset on landing alongside
## has_used_aerial. Kept independent per design: NA and JA are not
## mutually exclusive within the same jump.
var has_used_air_jump_attack: bool = false

var stun_timer: float = 0.0
var stun_just_started: bool = false
var pending_knockdown: bool = false

var is_blocking_low: bool = false
var current_health: float = 0.0
var is_defeated: bool = false

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
		print_rich("[P%d] %s" % [player_id, msg])


func _action(name: String) -> StringName:
	return StringName("%sP%d" % [name, player_id])


func _ready() -> void:
	facing_right = (player_id == 1)
	current_health = max_health

	# Animations are authored assuming the player faces right. Flipping
	# the parent Area2D scale mirrors every hitbox and hurtbox keyframe
	# into world space automatically, with no keyframe edits needed.
	if not facing_right:
		$Hitbox.scale.x = -1.0
		$Hurtbox.scale.x = -1.0

	_duplicate_owned_shapes()
	_duplicate_move_data()

	base_hurtbox_size = hurtbox_shape.size
	base_hurtbox_position = $Hurtbox/MainHurtbox.position

	_build_move_lookup()

	sprites.setup(animation_player, _all_move_sprite_names())
	sprites.set_facing(facing_right)
	sprites.animation_finished.connect(_on_sprites_animation_finished)

	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player:
			opponent = p
			break
	if not opponent:
		push_warning("[SETUP] No opponent found in 'players' group.")

	sprites.play_idle()

	# Lets GameManager hold a live reference to this instance without any
	# @export slot pointing across scenes — needed so upgrades picked in
	# the draft scene have someone to apply to after a scene change.
	EventBus.player_registered.emit(player_id, self)


# Shape resources assigned in the scene are shared across every instance
# unless duplicated. Without this, one player's attack animation
# resizing a hitbox or hurtbox shape mutates both players' shapes at
# once, since they are the same Resource object under the hood.
func _duplicate_owned_shapes() -> void:
	for shape_node in $Hitbox.get_children():
		if shape_node is CollisionShape2D and shape_node.shape:
			shape_node.shape = shape_node.shape.duplicate()

	for shape_node in $Hurtbox.get_children():
		if shape_node is CollisionShape2D and shape_node.shape:
			shape_node.shape = shape_node.shape.duplicate()

	hurtbox_shape = $Hurtbox/MainHurtbox.shape
	hitbox_shape = $Hitbox/MainHitbox.shape


# Same problem as the shapes above. Both players load the same MoveData
# resources from disk, so without this an upgrade that edits one
# player's move would edit both players' moves at once.
func _duplicate_move_data() -> void:
	N5 = N5.duplicate() if N5 else null
	N52 = N52.duplicate() if N52 else null
	N4 = N4.duplicate() if N4 else null
	N8 = N8.duplicate() if N8 else null
	N6 = N6.duplicate() if N6 else null
	N2 = N2.duplicate() if N2 else null
	NA = NA.duplicate() if NA else null
	S5 = S5.duplicate() if S5 else null
	S4 = S4.duplicate() if S4 else null
	S8 = S8.duplicate() if S8 else null
	S6 = S6.duplicate() if S6 else null
	S2 = S2.duplicate() if S2 else null
	SA = SA.duplicate() if SA else null
	JA = JA.duplicate() if JA else null

func _all_move_sprite_names() -> Array:
	var names: Array = []
	for move in [N5, N52, N4, N8, N6, N2, NA, S5, S4, S8, S6, S2, SA, JA]:
		if move:
			names.append(move.move_name)
	return names


func _build_move_lookup() -> void:
	all_moves.clear()
	normal_moves.clear()
	special_moves.clear()

	_register_move(N5, normal_moves, "neutral")
	_register_move(N4, normal_moves, "back")
	_register_move(N6, normal_moves, "forward")
	_register_move(N2, normal_moves, "crouching")
	_register_move(N8, normal_moves, "up")
	_register_move(NA, normal_moves, "aerial")
	_register_move(N52, normal_moves, "")

	_register_move(S5, special_moves, "neutral")
	_register_move(S4, special_moves, "back")
	_register_move(S6, special_moves, "forward")
	_register_move(S2, special_moves, "crouching")
	_register_move(S8, special_moves, "up")
	_register_move(SA, special_moves, "aerial")

	# JA isn't resolved by direction like a normal/special (see
	# _register_move below) — it's triggered directly off the Jump
	# button while airborne, so it only needs to land in all_moves
	# (for gatling lookups etc.), not in normal_moves/special_moves.
	if JA and JA.move_name not in locked_move_names:
		all_moves[JA.move_name] = JA


func _register_move(move: MoveData, dict: Dictionary, key: String) -> void:
	if not move:
		return
	if move.move_name in locked_move_names:
		return
	all_moves[move.move_name] = move
	dict[key] = move


func reset_health() -> void:
	current_health = max_health
	is_defeated = false
	EventBus.player_health_changed.emit(player_id, current_health)


# ──────────────────────────────────────────────────────────────────
#  Upgrade application — called by UpgradeData.apply_to(self)
#
#  Player owns the actual mutation. UpgradeData just says what kind of
#  change to make and with what values.

func apply_stat_boost(stat_name: StringName, amount: float, is_percent: bool) -> void:
	if not (stat_name in self):
		#push_warning("[P%d] apply_stat_boost: no property named '%s' on Player" % [player_id, stat_name])
		_dbg("[color=red][P%d] apply_stat_boost: no property named '%s' on Player" % [player_id, stat_name])
		return
	var current = get(stat_name)
	var new_value = current * (1.0 + amount / 100.0) if is_percent else current + amount
	
	set(stat_name, new_value)
	_dbg("[color=yellow][UPGRADE] stat_boost %s (Is percent?: %s): %s -> %s" % [stat_name, is_percent, current, new_value])
	# NOTE this is a stopgap solution for now, this will be called every time, so it's bad for runtime
	current_health = max_health
	walk_forward_speed = move_speed # Should fix speed option
	walk_backward_speed = move_speed # ^

## Takes in arrays of information needed for stats does checks to see if all arrays have the same
## length, currently assuming all arrays have correct info, then loops through each array and calls
## apply_stat_boost to properly do the stat boost
func apply_multi_stat_boost(stat_names_array: Array[String], ammounts_array: Array[float], is_percents_array: Array[bool]) -> void:
	var array_list = [stat_names_array, ammounts_array, is_percents_array]
	var target_length = array_list[0].size()
	var arrays_same_length : bool = true
	
	if target_length != 0:
		for arr in array_list:
			if arr.size() != target_length:
				if arr.size() > target_length:
					_dbg("[color=red][MULTI STAT] Array: %s length (%s) greater than target length: %s. Incomplete or extra data" % [arr, arr.size(), target_length])
				elif arr.size() < target_length:
					_dbg("[color=red][MULTI STAT] Array: %s length (%s) lesser than target length: %s. Incomplete or extra data" % [arr, arr.size(), target_length])
				arrays_same_length = false
	else:
		_dbg("[color=red][MULTI STAT] Array: %s length. Upgrade tagged as multiple stat but no array entries present" % target_length)
	
	if arrays_same_length == false:
		_dbg("[color=red][MULTI STAT] Could not get complete information")
	else:
		for i in range(target_length):
			apply_stat_boost(stat_names_array[i], ammounts_array[i], is_percents_array[i])


func unlock_move(move: MoveData) -> void:
	print("[TRACE] Player%d.unlock_move called with move=%s | locked_move_names=%s" % [player_id, (move.move_name if move else "null"), locked_move_names])
	if not move:
		#push_warning("[P%d] unlock_move called with a null MoveData" % player_id)
		_dbg("[color=red][P%d] unlock_move called with a null MoveData" % player_id)
		return
	if move.move_name not in locked_move_names:
		_dbg("[color=yellow][UPGRADE] unlock_move: '%s' wasn't locked, nothing to do" % move.move_name)
		return
	locked_move_names.erase(move.move_name)
	_build_move_lookup()
	_dbg("[color=yellow][UPGRADE] unlocked move '%s'" % move.move_name)


## target_upgrade_slot_id matches MoveData.upgrade_slot_id, so this can
## target a move's ROLE (e.g. "launcher") without caring which exact move
## currently fills that role.
func modify_move(target_upgrade_slot_id: StringName, property_name: StringName, delta: float) -> void:
	for move in all_moves.values():
		if move.upgrade_slot_id != target_upgrade_slot_id:
			continue
		if not (property_name in move):
			push_warning("[P%d] modify_move: MoveData '%s' has no property '%s'" % [player_id, move.move_name, property_name])
			continue
		var new_value = move.get(property_name) + delta
		move.set(property_name, new_value)
		move.is_upgraded = true
		move.upgrade_property_id = property_name
		_dbg("[UPGRADE] modify_move %s.%s -> %s" % [move.move_name, property_name, new_value])


# ──────────────────────────────────────────────────────────────────
#  Input buffering
#
#  Captures Jump/Normal/Special presses every physics frame no matter
#  what state the player is in, and lets that state (or whichever state
#  is entered next) pull them back out with _consume_buffer(). This is
#  what makes "press jump right as an attack's recovery ends" actually
#  jump instead of doing nothing, since the raw is_action_just_pressed
#  frame would otherwise happen while state != NEUTRAL and be lost.

func _capture_buffered_inputs() -> void:
	for action in ["Jump", "Normal", "Special"]:
		if Input.is_action_just_pressed(_action(action)):
			input_buffer[action] = input_buffer_frames


func _decay_input_buffer() -> void:
	# Only ticks down while NEUTRAL. While ATTACK/HITSTUN/BLOCKSTUN/
	# KNOCKDOWN, a buffered press just sits fully "hot" and waits —
	# otherwise a press captured early during a long attack (recovery
	# frequently runs well past input_buffer_frames) would expire
	# before the attack ever ends, and the buffer would never fire.
	# Once NEUTRAL is reached, _neutral_process()/_handle_jump() get a
	# chance to consume it that same frame (this runs after the match
	# statement); if it's still unconsumed after that it decays away
	# normally so a stale press doesn't linger forever.
	if state != State.NEUTRAL:
		return
	for action in input_buffer.keys():
		input_buffer[action] -= 1
		if input_buffer[action] <= 0:
			input_buffer.erase(action)


func _consume_buffer(action: String) -> bool:
	if input_buffer.get(action, 0) > 0:
		input_buffer.erase(action)
		return true
	return false


func _physics_process(delta: float) -> void:
	_capture_buffered_inputs()

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

	_decay_input_buffer()


func _neutral_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	_apply_gravity(delta)

	# JA: pressing Jump while already airborne triggers the jump-aerial
	# attack instead of _handle_jump() (which only ever fires while
	# grounded). Checked before _handle_jump()/movement so it can
	# short-circuit the frame exactly like the Normal/Special buffer
	# checks below do. Gate is independent from has_used_aerial (NA's
	# gate) by design — see the has_used_air_jump_attack declaration.
	if not was_on_floor and not has_used_air_jump_attack and JA and _consume_buffer("Jump"):
		has_used_air_jump_attack = true
		_start_attack(JA)
		return

	_handle_jump()
	_handle_crouch_input()
	_handle_horizontal_movement(delta)
	move_and_slide()
	_clamp_to_camera_bounds()
	var just_landed := is_on_floor() and not was_on_floor

	if just_landed:
		has_used_aerial = false
		has_used_air_jump_attack = false
		is_landing = true
		landed.emit()
		sprites.play_jump_land()

	_update_animation(just_landed)
	_update_hurtbox()
	sprites.update_block_warning(delta, _is_block_ready(), crouch_phase != CrouchPhase.NONE)

	# Consuming from the buffer instead of checking is_action_just_pressed
	# directly means a Normal/Special pressed during the previous ATTACK,
	# HITSTUN or BLOCKSTUN still comes out here as long as it's within
	# input_buffer_frames. Return immediately after starting an attack so
	# a same-frame Special buffer entry can't also fire and stomp it.
	if _consume_buffer("Normal"):
		var move = _resolve_move("normal")
		if move:
			_start_attack(move)
			return

	if _consume_buffer("Special"):
		var move = _resolve_move("special")
		if move:
			_start_attack(move)
			return


func _get_backward_action() -> StringName:
	return _action("Left") if facing_right else _action("Right")


func _is_block_ready() -> bool:
	if not is_on_floor():
		return false
	if not Input.is_action_pressed(_get_backward_action()):
		return false
	if crouch_phase != CrouchPhase.NONE:
		return Input.is_action_pressed(_action("Down"))
	return true


# OVERHEAD must be blocked standing, LOW must be blocked crouching,
# MID is blocked by either posture.
func _block_posture_beats_hit_level(hit_level: MoveData.HitLevel, was_crouching: bool) -> bool:
	match hit_level:
		MoveData.HitLevel.OVERHEAD:
			return not was_crouching
		MoveData.HitLevel.LOW:
			return was_crouching
		_:
			return true


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
		elif _is_input_forward(dir):
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

	state = State.ATTACK
	current_move = move
	attack_frame = 0
	attack_instance_id += 1
	_projectile_fired_this_attack = false
	hit_connected = false
	_hit_registered_this_activation = false
	_hitbox_was_disabled_last_frame = $Hitbox/MainHitbox.disabled
	gatling_input_buffered = ""
	gatling_buffer_timer = 0
	gatling_cancel_window_open = false

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


func _attack_process(delta: float) -> void:
	var move_velocity := velocity

	if not is_on_floor() and current_move:
		move_velocity.y *= 0.85
		move_velocity.y += gravity * delta * 0.6
	else:
		move_velocity.y = 0.0

	if current_move and current_move.is_advancing and pushback_velocity_x == 0.0:
		if attack_frame == 1:
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

	# Buffering runs every attack frame regardless of hit-confirm or the
	# cancel window, so an early press isn't lost while waiting for
	# either of those to become true.
	_update_gatling_buffer()

	if hit_connected and gatling_cancel_window_open:
		_try_cancel_gatling()

	_update_hitbox_activation_tracking()
	if not _hit_registered_this_activation:
		_check_hit()

	if attack_frame >= total_frames:
		_end_attack()


func _update_gatling_buffer() -> void:
	if Input.is_action_just_pressed(_action("Normal")):
		gatling_input_buffered = _action("Normal")
		gatling_buffer_timer = gatling_buffer_frames
		return

	if gatling_input_buffered != "":
		gatling_buffer_timer -= 1
		if gatling_buffer_timer <= 0:
			gatling_input_buffered = ""
			gatling_buffer_timer = 0


# Call this from an AnimationPlayer "Call Method" track key, placed at
# whatever frame you want gatling cancels to become legal for this move
# (typically right as recovery starts). Hit-confirm gated: even with the
# window open, _try_cancel_gatling() below only fires if hit_connected is
# already true, so a whiffed move can never cancel — only a hit or a
# blocked hit opens up the follow-up.
func open_gatling_cancel_window() -> void:
	gatling_cancel_window_open = true


# Optional companion for a bounded cancel window — add a second Call
# Method key later in the same animation if you want cancels to stop
# being legal before the move fully ends. Not required: the window
# always resets to closed on the next _start_attack() regardless.
func close_gatling_cancel_window() -> void:
	gatling_cancel_window_open = false


func _try_cancel_gatling() -> void:
	if gatling_input_buffered == _action("Normal") and current_move.gatlings_into.size() > 0:
		# gatlings_into is Array[StringName] but all_moves is keyed by
		# move_name (String). String/StringName compare equal with ==,
		# but Dictionary.has() uses hashed key lookup and won't match
		# across the two types — cast explicitly or the cancel silently
		# no-ops even though the target move exists in all_moves.
		var gatling_name = String(current_move.gatlings_into[0])
		if all_moves.has(gatling_name):
			_start_attack(all_moves[gatling_name])
		else:
			_dbg("[color=red][GATLING] '%s' not found in all_moves — check gatlings_into spelling/locked state" % gatling_name)


# Call this from an AnimationPlayer "Call Method" track key, placed at
# whatever frame the projectile should actually leave the player's hand,
# same pattern as open_gatling_cancel_window(). current_move must have
# fires_projectile and projectile_scene set on its MoveData resource.
func fire_projectile() -> void:
	if not current_move or not current_move.fires_projectile:
		return

	if _projectile_fired_this_attack:
		return

	if not current_move.projectile_scene:
		_dbg("[color=red][PROJECTILE] '%s' has fires_projectile=true but no projectile_scene assigned" % current_move.move_name)
		return

	var projectile = current_move.projectile_scene.instantiate()
	if not projectile is Projectile:
		_dbg("[color=red][PROJECTILE] projectile_scene root for '%s' is not a Projectile" % current_move.move_name)
		return

	_projectile_fired_this_attack = true
	projectile.setup(self, opponent)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = _projectile_spawn_position(current_move)


func _projectile_spawn_position(move: MoveData) -> Vector2:
	var offset := move.projectile_spawn_offset
	offset.x *= 1.0 if facing_right else -1.0
	return global_position + offset


func _end_attack() -> void:
	var was_airborne := not is_on_floor()

	state = State.NEUTRAL
	attack_frame = 0
	current_move = null
	gatling_input_buffered = ""
	gatling_buffer_timer = 0

	if was_airborne:
		air_horizontal_velocity = velocity.x

	sprites.hide_attack_sprites()
	_resume_crouch_or_update_animation()


# Multi-hit moves (NA etc.) toggle MainHitbox's disabled property on
# and off multiple times within one animation via Call Method /
# animation track keys. Each time it goes from disabled -> enabled,
# that's a fresh activation, so it should be able to land a hit again
# even though hit_connected is already permanently true from an
# earlier activation this same attack.
func _update_hitbox_activation_tracking() -> void:
	var hitbox_area_shape = $Hitbox/MainHitbox
	var is_disabled_now = hitbox_area_shape.disabled

	if _hitbox_was_disabled_last_frame and not is_disabled_now:
		_hit_registered_this_activation = false

	_hitbox_was_disabled_last_frame = is_disabled_now


func _check_hit() -> void:
	if not opponent:
		return

	var hitbox_area_shape = $Hitbox/MainHitbox
	if hitbox_area_shape.disabled:
		return

	var opponent_hurtbox = opponent.get_node("Hurtbox")
	for area in $Hitbox.get_overlapping_areas():
		if area == opponent_hurtbox or area.get_parent() == opponent_hurtbox:
			var was_blocked = opponent.take_hit(current_move, self)
			hit_connected = true
			_hit_registered_this_activation = true
			EventBus.player_hit_landed.emit(player_id, current_move.move_name, was_blocked)
			EventBus.hit_confirmed.emit(hitbox_area_shape.global_position, current_move, self, opponent, was_blocked)
			
			EventBus.npc_cheer.emit() # Just here to call for the npc's to cheer when a player is hit
			
			if was_blocked:
				_apply_pushback()
			return


func _direction_away_from(other: Node2D) -> float:
	return -1.0 if other.global_position.x > global_position.x else 1.0


func _apply_pushback() -> void:
	if not current_move or not opponent:
		return
	pushback_velocity_x = _direction_away_from(opponent) * current_move.pushback_on_block


# Shared countdown for hitstun, blockstun and knockdown. Skips the
# first tick right after a state change, since the caller may set
# state mid frame before this player's own physics step has run.
func _tick_stun_timer(delta: float) -> bool:
	if stun_just_started:
		stun_just_started = false
		return false
	stun_timer -= delta
	return stun_timer <= 0.0


func _hitstun_process(delta: float) -> void:
	# This branch only runs for a plain grounded hit (pending_knockdown
	# false), where zeroing velocity.y is correct/wanted. If a launcher
	# hit ever ends up in here, its upward velocity gets silently wiped
	# right here — see the move_is_launcher note in _resolve_hit().
	if is_on_floor() and not pending_knockdown:
		pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, pushback_deceleration * delta)
		velocity.x = pushback_velocity_x
		velocity.y = 0.0
		move_and_slide()

		if _tick_stun_timer(delta):
			state = State.NEUTRAL
			hitstun_finished.emit()
			_resume_crouch_or_update_animation()
		return

	# Airborne hitstun, from a launcher or a hit taken mid air, ignores
	# the stun timer and just falls until it lands, then becomes a
	# knockdown instead of standing back up mid air.
	_apply_gravity(delta)
	pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, pushback_deceleration * delta)
	velocity.x = pushback_velocity_x
	move_and_slide()

	if is_on_floor():
		pending_knockdown = false
		stun_timer = knockdown_duration
		stun_just_started = true
		$Hurtbox/MainHurtbox.disabled = true
		state = State.KNOCKDOWN


func _blockstun_process(delta: float) -> void:
	pushback_velocity_x = move_toward(pushback_velocity_x, 0.0, pushback_deceleration * delta)
	velocity.x = pushback_velocity_x
	velocity.y = 0.0
	move_and_slide()

	sprites.play_block_idle(is_blocking_low)
	EventBus.player_blocking_low[player_id] = is_blocking_low

	if not _tick_stun_timer(delta):
		return

	state = State.NEUTRAL
	sprites.hide_block_sprites()
	_resume_crouch_or_update_animation()


func _knockdown_process(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, pushback_deceleration * delta)
	move_and_slide()

	if not _tick_stun_timer(delta):
		return

	$Hurtbox/MainHurtbox.disabled = false
	state = State.NEUTRAL
	_update_animation(false)


# If still holding crouch when returning to NEUTRAL, go straight back
# to crouch idle instead of showing standing idle for one frame and
# re-triggering the crouch down transition right after.
func _resume_crouch_or_update_animation() -> void:
	if is_on_floor() and Input.is_action_pressed(_action("Down")):
		wants_to_crouch = true
		crouch_phase = CrouchPhase.LOOP
		sprites.play_crouch_idle()
	else:
		_update_animation(false)


func _min_visible_stun_frames(anim_name: String) -> int:
	if not animation_player.has_animation(anim_name):
		return 0
	return int(ceil(animation_player.get_animation(anim_name).length * 60.0))


# Whenever this player is hit (blocked or not), any collision shapes an
# animation left switched on mid-swing need to be forced off rather
# than trusting the interrupted animation to reach its own "off"
# keyframe — it never will, since the animation gets cut short by
# hitstun/blockstun right here.
#  - Hitbox shapes: if this player was mid-attack (e.g. traded hits),
#    their own attack should stop threatening the opponent immediately.
#  - Hurtbox "sub" shapes: some moves enable an extra vulnerable area
#    (e.g. an extended limb) only during certain frames. MainHurtbox is
#    left alone — its own enabled state is managed separately elsewhere
#    (e.g. knockdown invulnerability) and it should always stay live.
func _disable_combat_shapes_on_hit() -> void:
	for shape_node in $Hitbox.get_children():
		if shape_node is CollisionShape2D:
			shape_node.disabled = true

	for shape_node in $Hurtbox.get_children():
		if shape_node is CollisionShape2D and shape_node.name != "MainHurtbox":
			shape_node.disabled = true


func take_hit(move_data: MoveData, attacker: Node2D) -> bool:
	var was_crouching = (crouch_phase != CrouchPhase.NONE)

	crouch_phase = CrouchPhase.NONE
	wants_to_crouch = false
	is_landing = false

	_disable_combat_shapes_on_hit()

	# Blocking is only legal from NEUTRAL (reacting to a hit) or from
	# BLOCKSTUN (holding block through the rest of a multi-hit string).
	# Without this, ATTACK counted too — e.g. N4 is input by holding
	# back, and that same held-back input stays true for the whole
	# swing, so an attacking player who happened to be holding back
	# would get treated as blocking instead of getting counter-hit.
	# HITSTUN and KNOCKDOWN are excluded for the same reason: you
	# shouldn't be able to block while already reeling from a hit.
	var can_block_right_now = state == State.NEUTRAL or state == State.BLOCKSTUN
	var block_ready = can_block_right_now and _is_block_ready() and _block_posture_beats_hit_level(move_data.hit_level, was_crouching)
	if block_ready:
		_resolve_block(move_data, attacker, was_crouching)
		return true

	_resolve_hit(move_data, attacker, was_crouching)
	return false


func _resolve_block(move_data: MoveData, attacker: Node2D, was_crouching: bool) -> void:
	is_blocking_low = was_crouching
	pushback_velocity_x = _direction_away_from(attacker) * move_data.block_knock_back

	var stun_frames = max(move_data.recovery + move_data.block_advantage, 0)
	var reaction_anim := "crouch_block_idle" if is_blocking_low else "block_idle"
	stun_frames = max(stun_frames, _min_visible_stun_frames(reaction_anim))

	stun_timer = stun_frames / 60.0
	stun_just_started = true
	state = State.BLOCKSTUN

	call_deferred("_apply_block_reaction_visuals")


func _resolve_hit(move_data: MoveData, attacker: Node2D, was_crouching: bool) -> void:
	current_health = max(current_health - move_data.damage, 0.0)
	EventBus.player_health_changed.emit(player_id, current_health)

	if current_health <= 0.0 and not is_defeated:
		is_defeated = true
		EventBus.player_defeated.emit(player_id)

	# is_launcher is treated as true if EITHER the checkbox is on OR
	# launcher_strength is non-zero. This exists because "set
	# launcher_strength, forget to also tick is_launcher" is a really
	# easy mistake to make in the inspector, and the failure mode is
	# silent: pending_knockdown stays false, so the grounded branch of
	# _hitstun_process runs and its `velocity.y = 0.0` (needed so a
	# normal ground hit doesn't keep any stray vertical velocity) wipes
	# out the upward velocity before it's ever visible.
	var move_is_launcher = move_data.is_launcher or move_data.launcher_strength > 0.0

	pending_knockdown = move_is_launcher or not is_on_floor()
	pushback_velocity_x = _direction_away_from(attacker) * move_data.knock_back
	if move_is_launcher:
		velocity.y = -move_data.launcher_strength

	_dbg("[RESOLVE HIT] '%s' is_launcher=%s launcher_strength=%.1f -> move_is_launcher=%s pending_knockdown=%s velocity.y=%.1f" % [
		move_data.move_name, move_data.is_launcher, move_data.launcher_strength, move_is_launcher, pending_knockdown, velocity.y
	])

	var hitstun_frames = move_data.hitstun
	var reaction_anim := "crouch_hit" if was_crouching else "mid_hit"
	hitstun_frames = max(hitstun_frames, _min_visible_stun_frames(reaction_anim))

	stun_timer = hitstun_frames / 60.0
	stun_just_started = true
	state = State.HITSTUN

	call_deferred("_apply_hit_reaction_visuals", was_crouching)


func _apply_block_reaction_visuals() -> void:
	sprites.play_block_idle(is_blocking_low, true)


func _apply_hit_reaction_visuals(was_crouching: bool) -> void:
	sprites.play_hit_reaction(was_crouching)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += gravity * delta


func _handle_jump() -> void:
	if not is_on_floor() or crouch_phase != CrouchPhase.NONE:
		return
	# Consuming from the buffer (instead of checking
	# is_action_just_pressed directly) is what lets a jump pressed a few
	# frames early — e.g. right before an attack's recovery ends — still
	# come out the instant NEUTRAL is able to act on it.
	if not _consume_buffer("Jump"):
		return
	velocity.y = jump_velocity
	air_horizontal_velocity = _get_horizontal_input() * _current_walk_speed()
	is_landing = false


func _handle_crouch_input() -> void:
	var down_pressed = is_on_floor() and Input.is_action_pressed(_action("Down"))

	if down_pressed and crouch_phase == CrouchPhase.NONE:
		wants_to_crouch = true
		crouch_phase = CrouchPhase.TRANSITION_DOWN
		sprites.play_crouch_down()
	elif not down_pressed and crouch_phase == CrouchPhase.LOOP:
		wants_to_crouch = false
		crouch_phase = CrouchPhase.STAND_UP
		sprites.play_crouch_up()
	elif not down_pressed and crouch_phase == CrouchPhase.TRANSITION_DOWN and wants_to_crouch:
		wants_to_crouch = false
	elif down_pressed and crouch_phase == CrouchPhase.TRANSITION_DOWN and not wants_to_crouch:
		wants_to_crouch = true


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
	var left := Input.is_action_pressed(_action("Left"))
	var right := Input.is_action_pressed(_action("Right"))
	if left == right:
		return Direction.NONE
	return Direction.LEFT if left else Direction.RIGHT


func _direction_to_float(dir: int) -> float:
	match dir:
		Direction.LEFT:
			return -1.0
		Direction.RIGHT:
			return 1.0
	return 0.0


func _get_horizontal_input() -> float:
	var dir := 0.0
	if Input.is_action_pressed(_action("Left")):
		dir -= 1.0
	if Input.is_action_pressed(_action("Right")):
		dir += 1.0
	return dir


# Forward and backward are relative to which way this player faces, not
# raw world direction. Used everywhere speed and animation choice need
# to agree on what forward means.
func _is_input_forward(dir: float) -> bool:
	return (dir > 0.0) == facing_right


func _current_walk_speed() -> float:
	var dir := _get_horizontal_input()
	if dir == 0.0:
		return walk_forward_speed
	return walk_forward_speed if _is_input_forward(dir) else walk_backward_speed


func _speed_for_direction(dir: int) -> float:
	var is_forward := (dir == Direction.RIGHT) == facing_right
	return walk_forward_speed if is_forward else walk_backward_speed


func _update_animation(just_landed: bool = false) -> void:
	if is_landing and not just_landed:
		return

	if crouch_phase != CrouchPhase.NONE:
		return

	if not is_on_floor():
		match _get_jump_phase():
			JumpPhase.RISE:
				sprites.play_jump_rise()
			JumpPhase.PEAK:
				sprites.play_jump_peak()
			JumpPhase.FALL:
				sprites.play_jump_fall()
		return

	if is_landing:
		return

	var direction := _get_horizontal_input()
	if direction == 0.0:
		sprites.play_idle()
		last_direction = Direction.NONE
	else:
		sprites.play_walk(_is_input_forward(direction))


func _get_jump_phase() -> JumpPhase:
	if velocity.y < -jump_apex_threshold:
		return JumpPhase.RISE
	if velocity.y > jump_apex_threshold:
		return JumpPhase.FALL
	return JumpPhase.PEAK


func _on_sprites_animation_finished(anim_name: String) -> void:
	match anim_name:
		"jump_land":
			is_landing = false
			_update_animation(false)

		"crouch_down":
			if wants_to_crouch:
				crouch_phase = CrouchPhase.LOOP
				sprites.play_crouch_idle()
			else:
				crouch_phase = CrouchPhase.STAND_UP
				sprites.play_crouch_up()

		"crouch_up":
			crouch_phase = CrouchPhase.NONE
			wants_to_crouch = false
			_update_animation(false)


func freeze_until_landing() -> void:
	animation_player.pause()
	await landed
	if animation_player.current_animation == "jump_peak":
		animation_player.play()


func freeze_until_hitstun_recovery() -> void:
	animation_player.pause()
	await hitstun_finished
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


func _clamp_to_camera_bounds() -> void:
	if not camera:
		return

	var left_limit = camera.global_position.x - (get_viewport_rect().size.x / (2 * camera.zoom.x))
	var right_limit = camera.global_position.x + (get_viewport_rect().size.x / (2 * camera.zoom.x))
	var padding = 40.0

	global_position.x = clamp(global_position.x, left_limit + padding, right_limit - padding)
