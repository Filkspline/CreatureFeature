extends Area2D
class_name Projectile

# Bidirectional projectile.
#
# Phase 1 - UNLAUNCHED: floats forward slowly, owned by whoever spawned
# it. Only that owner can hit it with their own attack to send it flying
# (deflectable). The owner can keep doing this for as long as the
# projectile is alive, not just once.
#
# Phase 2 - LAUNCHED (a volley): once it's moving, whoever does NOT
# currently own it can hit it back with their own attack (returnable).
# Doing so flips ownership to them - "it becomes their projectile" - and
# the hit's knock_back is ADDED on top of its current speed rather than
# replacing it, so a rally gets faster with every return. After a
# return, the new owner is free to keep re-hitting it too, same as
# above.
#
# Whichever player currently does NOT own it is the one who takes
# damage if it reaches their Hurtbox. That flows straight into the same
# take_hit() pipeline a normal Hitbox/Hurtbox hit uses, so
# blocking/hitstun/hit-level all just work.

@export_group("Setup")
## Which player_id spawned this. Only used as a fallback if setup() was
## never called with a direct owner_player reference.
@export var owner_player_id: int = 1
## If true and target_player wasn't set via setup(), automatically finds
## the other Player in the "players" group.
@export var auto_find_target: bool = true

@export_group("Flight - Idle")
## Constant forward speed before this projectile has ever been hit.
@export var idle_speed: float = 60.0
## Direction used only if no owner_player is available to read facing
## from (e.g. testing this scene standalone in the editor).
@export var fallback_direction: Vector2 = Vector2.RIGHT
@export var apply_gravity: bool = false

@export_group("Flight - Deflect & Return")
## Whether this projectile can be hit at all, by anyone.
@export var deflectable: bool = true
## Whether, once launched, whoever does NOT currently own it can hit it
## back, flipping ownership and sending it the other way.
@export var returnable: bool = true
## Multiplies a hit's knock_back before it's added to the projectile's
## current speed.
@export var launch_speed_multiplier: float = 1.0
## Floor for speed after any deflect/return.
@export var min_launch_speed: float = 300.0
## Optional ceiling so a rally can't accelerate forever. 0 = uncapped.
@export var max_launch_speed: float = 1400.0
## How fast speed decays back down toward idle_speed between hits.
@export var deceleration: float = 250.0

@export_group("Impact")
## Drives damage/knockback/hitstun/hit_level/blocking for whoever this
## projectile currently counts as "against". Passed straight into
## Player.take_hit(), so any MoveData resource works.
@export var impact_move_data: MoveData
@export var destroy_on_hit: bool = true
@export var destroy_on_block: bool = true
## Routes the impact through EventBus.hit_confirmed, so your existing
## HitEffectManager particles fire the same as a normal hit.
@export var emit_hit_effects: bool = true
## Cooldown before the target can be hit again by this projectile, only
## relevant if destroy_on_hit/destroy_on_block is false and the
## projectile keeps flying through instead of dying.
@export var target_hit_cooldown: float = 0.3

@export_group("Lifetime / Safety")
@export var max_lifetime: float = 6.0
@export var max_travel_distance: float = 3000.0

@export_group("Visual")
## Only used if no Sprite2D child has a texture.
@export var placeholder_radius: float = 16.0
@export var placeholder_color: Color = Color(1.0, 0.85, 0.2)
@export var player_one_color: Color = Color.WHITE
@export var player_two_color: Color = Color("639bff")

@export_group("Bounce FX")
## How big the squash-and-stretch overshoot is on spawn.
@export var spawn_punch_scale: float = 1.35
@export var spawn_tween_duration: float = 0.25
## Vertical drift of the idle bob, in pixels.
@export var idle_bob_amplitude: float = 4.0
@export var idle_bob_duration: float = 0.6
## Scale punch applied on every deflect/return hit.
@export var hit_bounce_scale: Vector2 = Vector2(1.4, 0.7)
@export var hit_bounce_duration: float = 0.12
@export var death_punch_scale: float = 1.6
@export var death_punch_duration: float = 0.2

@export_group("Sprite Sheet")
## Seconds each frame is held for. The Sprite2D at "Sprite" must have
## hframes/vframes set up in the editor to slice its 9-frame sheet.
@export var frame_duration: float = 0.06

@export_group("Debug")
@export var debug: bool = true

@export_flags_2d_physics var projectile_collision_layer: int = 1:
	set(value):
		projectile_collision_layer = value
		collision_layer = value
@export_flags_2d_physics var projectile_collision_mask: int = 1:
	set(value):
		projectile_collision_mask = value
		collision_mask = value

const SPAWN_FRAMES: Array[int] = [0, 1, 2, 3]
const IDLE_FRAMES: Array[int] = [4, 5]
const DEATH_FRAMES: Array[int] = [6, 7, 8]
## Frame 6 doubles as the death sequence's first frame and as a quick
## flash whenever the projectile gets hit without dying.
const HIT_FLASH_FRAME := 6

var owner_player: Player = null
var target_player: Player = null

var velocity: Vector2 = Vector2.ZERO

var _facing_dir: float = 1.0
var _launched: bool = false
var _spawn_position: Vector2
var _life: float = 0.0
var _dying: bool = false

# Tracks the last attack_instance_id each player has already used to
# deflect this projectile, so the same swing can't register twice while
# its hitbox overlaps across several frames, but a fresh swing later
# always counts again.
var _resolved_attack_ids: Dictionary = {}

# True while a hurtbox contact is being held pending because the target
# was already mid-attack when contact was detected - gives them a real
# chance to deflect instead of eating a hit their own swing was about
# to counter. Held for as long as target_player.current_move stays
# non-null; deflect is checked first every frame, so the moment their
# hitbox goes active it wins before this ever resolves as damage.
var _pending_hit: bool = false
# Safety net only, in case current_move somehow never clears.
var _pending_hit_timer: float = 0.0
const PENDING_HIT_MAX_HOLD: float = 1.0

var _target_hit_cooldown_timer: float = 0.0

var _sprite: Sprite2D = null
var _sprite_base_scale: Vector2 = Vector2.ONE
var _sprite_base_position: Vector2 = Vector2.ZERO
var _idle_bob_tween: Tween = null

# Manual frame-sequence playback for the Sprite2D sheet, since Sprite2D
# has no built-in animation player.
var _sequence_frames: Array[int] = []
var _sequence_index: int = 0
var _sequence_loop: bool = false
var _sequence_timer: float = 0.0
var _playing_death: bool = false


# Call this right after instantiating, before add_child().
func setup(spawning_player: Player, opposing_player: Player = null) -> void:
	owner_player = spawning_player
	if spawning_player:
		owner_player_id = spawning_player.player_id
	target_player = opposing_player


func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = projectile_collision_layer
	collision_mask = projectile_collision_mask

	_spawn_position = global_position

	if not owner_player:
		owner_player = _find_player_by_id(owner_player_id)
	if not target_player and auto_find_target:
		target_player = _find_opponent_of(owner_player)

	if owner_player:
		_facing_dir = 1.0 if owner_player.facing_right else -1.0
	elif fallback_direction.x != 0.0:
		_facing_dir = signf(fallback_direction.x)

	velocity = Vector2(idle_speed * _facing_dir, 0.0)

	if not target_player:
		_dbg("[SETUP] no target_player found - this projectile can still fly and be deflected, but will never resolve a hit.")
	if not impact_move_data:
		_dbg("[SETUP] no impact_move_data assigned - reaching a target will just despawn this with no damage.")

	_setup_sprite()
	_apply_owner_color()
	_update_sprite_facing()
	_play_spawn_sequence()

	queue_redraw()


func _setup_sprite() -> void:
	var sprite_node := get_node_or_null("Sprite")
	if not sprite_node is Sprite2D:
		return

	_sprite = sprite_node
	_sprite_base_scale = _sprite.scale
	_sprite_base_position = _sprite.position


func _apply_owner_color() -> void:
	modulate = player_two_color if owner_player_id == 2 else player_one_color


func _physics_process(delta: float) -> void:
	_update_sprite_sequence(delta)

	if _dying:
		return

	_life += delta
	if _life >= max_lifetime:
		_dbg("[LIFETIME] max_lifetime reached, dying")
		_play_death_and_free()
		return

	var deflected_this_frame: bool = _check_deflect()

	if apply_gravity:
		velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, idle_speed * _facing_dir, deceleration * delta)

	global_position += velocity * delta

	if global_position.distance_to(_spawn_position) >= max_travel_distance:
		_dbg("[LIFETIME] max_travel_distance reached, dying")
		_play_death_and_free()
		return

	if _target_hit_cooldown_timer > 0.0:
		_target_hit_cooldown_timer -= delta

	# A deflect this frame is fully resolved above - never also let the
	# same frame's contact resolve as damage, and cancel any pending
	# hit from a prior frame too.
	if deflected_this_frame:
		_pending_hit = false
		_pending_hit_timer = 0.0
		return

	if _pending_hit:
		_pending_hit_timer += delta
		if target_player and target_player.current_move and _pending_hit_timer < PENDING_HIT_MAX_HOLD:
			return
		_resolve_target_hit()
		_pending_hit = false
		_pending_hit_timer = 0.0
		return

	if _target_hit_cooldown_timer <= 0.0 and _target_hurtbox_overlapping():
		if target_player and target_player.current_move:
			_pending_hit = true
			_pending_hit_timer = 0.0
		else:
			_resolve_target_hit()


# The owner can always try to deflect their own projectile, checked
# first every frame. Once launched, whoever does NOT currently own it
# can return it instead, if returnable. Returns true if a deflect
# actually happened this frame.
func _check_deflect() -> bool:
	if not deflectable:
		return false
	if _try_deflect(owner_player):
		return true
	if _launched and returnable:
		return _try_deflect(target_player)
	return false


# Mirrors Player._check_hit(): only counts as a hit during the hitting
# player's actual active frames, read straight off their own
# current_move. Gated per-player by attack_instance_id so the same
# swing can't deflect twice while it overlaps across frames, but a
# later swing with the same MoveData resource still counts.
func _try_deflect(hitting_player: Player) -> bool:
	if not hitting_player:
		return false

	var move := hitting_player.current_move
	if not move:
		return false
	if _resolved_attack_ids.get(hitting_player, -1) == hitting_player.attack_instance_id:
		return false

	var hitbox_shape: CollisionShape2D = hitting_player.get_node_or_null("Hitbox/MainHitbox")
	if not hitbox_shape or hitbox_shape.disabled:
		return false

	var hitbox_area: Area2D = hitting_player.get_node_or_null("Hitbox")
	if not hitbox_area or hitbox_area not in get_overlapping_areas():
		return false

	_resolved_attack_ids[hitting_player] = hitting_player.attack_instance_id
	_apply_deflect(hitting_player, move)
	return true


func _apply_deflect(hitting_player: Player, move: MoveData) -> void:
	var was_return: bool = _launched and hitting_player != owner_player
	var was_first_launch: bool = not _launched
	if was_return:
		var previous_owner := owner_player
		owner_player = hitting_player
		target_player = previous_owner
		owner_player_id = hitting_player.player_id

	# Added, not replaced - a returned hit stacks its knock_back on top
	# of whatever speed the projectile already had.
	var current_speed: float = absf(velocity.x)
	var added_speed: float = absf(move.knock_back) * launch_speed_multiplier
	var new_speed: float = maxf(current_speed + added_speed, min_launch_speed)
	if max_launch_speed > 0.0:
		new_speed = minf(new_speed, max_launch_speed)

	_facing_dir = 1.0 if hitting_player.facing_right else -1.0
	velocity.x = new_speed * _facing_dir

	_launched = true
	_update_sprite_facing()
	_play_hit_bounce()

	var descriptor := "RE-HIT by owner"
	if was_return:
		descriptor = "RETURNED (now player %d's)" % hitting_player.player_id
	elif was_first_launch:
		descriptor = "LAUNCHED"

	_dbg("[DEFLECT] %s | player=%d move='%s' knock_back=%.1f | %.1f -> %.1f" % [
		descriptor, hitting_player.player_id, move.move_name, move.knock_back, current_speed, new_speed
	])


func _target_hurtbox_overlapping() -> bool:
	if not target_player:
		return false
	var target_hurtbox: Area2D = target_player.get_node_or_null("Hurtbox")
	return target_hurtbox and target_hurtbox in get_overlapping_areas()


func _resolve_target_hit() -> void:
	if not target_player:
		return

	if not impact_move_data:
		_dbg("[IMPACT] reached target with no impact_move_data, dying without a hit")
		_play_death_and_free()
		return

	var was_blocked: bool = target_player.take_hit(impact_move_data, self)

	if owner_player:
		EventBus.player_hit_landed.emit(owner_player.player_id, impact_move_data.move_name, was_blocked)
	if emit_hit_effects:
		EventBus.hit_confirmed.emit(global_position, impact_move_data, self, target_player, was_blocked)

	_dbg("[IMPACT] hit target | blocked=%s damage=%.1f" % [was_blocked, impact_move_data.damage])

	var should_destroy := (was_blocked and destroy_on_block) or (not was_blocked and destroy_on_hit)
	if should_destroy:
		_play_death_and_free()
	else:
		_target_hit_cooldown_timer = target_hit_cooldown
		_play_hit_bounce()


func _find_player_by_id(id: int) -> Player:
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p.player_id == id:
			return p
	return null


func _find_opponent_of(from_player: Player) -> Player:
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p != from_player:
			return p
	return null


func _update_sprite_facing() -> void:
	if _sprite:
		_sprite.flip_h = _facing_dir < 0.0


# Steps the manual frame sequence forward at frame_duration intervals.
# Looping sequences (idle) wrap back to the start; one-shot sequences
# (spawn, death) hold their last frame and hand off via
# _on_sequence_finished().
func _update_sprite_sequence(delta: float) -> void:
	if not _sprite or _sequence_frames.is_empty():
		return

	_sequence_timer += delta
	if _sequence_timer < frame_duration:
		return
	_sequence_timer -= frame_duration

	_sequence_index += 1
	if _sequence_index < _sequence_frames.size():
		_sprite.frame = _sequence_frames[_sequence_index]
		return

	if _sequence_loop:
		_sequence_index = 0
		_sprite.frame = _sequence_frames[0]
		return

	_sequence_index = _sequence_frames.size() - 1
	_on_sequence_finished()


func _on_sequence_finished() -> void:
	if _playing_death:
		queue_free()
		return
	_play_idle()


func _play_sequence(frames: Array[int], loop: bool) -> void:
	if not _sprite:
		return
	_sequence_frames = frames
	_sequence_index = 0
	_sequence_timer = 0.0
	_sequence_loop = loop
	_sprite.frame = frames[0]


func _play_spawn_sequence() -> void:
	if not _sprite:
		return

	_bounce_scale(_sprite_base_scale * 0.2, _sprite_base_scale * spawn_punch_scale, _sprite_base_scale, spawn_tween_duration)
	_play_sequence(SPAWN_FRAMES, false)


func _play_idle() -> void:
	_play_sequence(IDLE_FRAMES, true)
	_start_idle_bob()


func _start_idle_bob() -> void:
	if not _sprite:
		return

	if _idle_bob_tween and _idle_bob_tween.is_valid():
		_idle_bob_tween.kill()

	_sprite.position = _sprite_base_position
	_idle_bob_tween = create_tween()
	_idle_bob_tween.set_loops()
	_idle_bob_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_bob_tween.tween_property(_sprite, "position:y", _sprite_base_position.y - idle_bob_amplitude, idle_bob_duration)
	_idle_bob_tween.tween_property(_sprite, "position:y", _sprite_base_position.y + idle_bob_amplitude, idle_bob_duration)


# Flashes the shared hit frame (also the death sequence's first frame)
# then bounces back to idle, unless a death sequence starts in the
# meantime and takes over.
func _play_hit_bounce() -> void:
	if not _sprite:
		return

	if _idle_bob_tween and _idle_bob_tween.is_valid():
		_idle_bob_tween.kill()

	_sequence_frames = []
	_sprite.frame = HIT_FLASH_FRAME

	var tween := _bounce_scale(_sprite.scale, _sprite_base_scale * hit_bounce_scale, _sprite_base_scale, hit_bounce_duration)
	tween.tween_callback(_play_idle)


func _play_death_and_free() -> void:
	if _dying:
		return
	_dying = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if _idle_bob_tween and _idle_bob_tween.is_valid():
		_idle_bob_tween.kill()

	if not _sprite:
		queue_free()
		return

	_playing_death = true
	_play_sequence(DEATH_FRAMES, false)
	_bounce_scale(_sprite.scale, _sprite_base_scale * death_punch_scale, _sprite_base_scale, death_punch_duration)


# Shared squash-and-stretch helper: snaps to from_scale, overshoots to
# punch_scale, then settles back to end_scale. Returns the tween so
# callers can chain onto it.
func _bounce_scale(from_scale: Vector2, punch_scale: Vector2, end_scale: Vector2, duration: float) -> Tween:
	_sprite.scale = from_scale
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", punch_scale, duration * 0.6)
	tween.tween_property(_sprite, "scale", end_scale, duration * 0.4)
	return tween


func _draw() -> void:
	if _sprite:
		return
	var sprite := get_node_or_null("Sprite")
	if sprite and sprite is Sprite2D and sprite.texture:
		return
	draw_circle(Vector2.ZERO, placeholder_radius, placeholder_color)


func _dbg(msg: String) -> void:
	if debug:
		print("[Projectile] ", msg)
