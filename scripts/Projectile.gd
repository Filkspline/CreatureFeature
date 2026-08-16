extends Area2D
class_name Projectile

# Bidirectional projectile.
#
# Phase 1 — UNLAUNCHED: floats forward slowly, owned by whoever spawned
# it. Only that owner can hit it with their own attack to send it flying
# (deflectable).
#
# Phase 2 — LAUNCHED (a volley): once it's moving, whoever does NOT
# currently own it can hit it back with their own attack (returnable).
# Doing so flips ownership to them — "it becomes their projectile" — and
# the hit's knock_back is ADDED on top of its current speed rather than
# replacing it, so a rally gets faster with every return.
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

@export_group("Flight — Idle")
## Constant forward speed before this projectile has ever been hit.
@export var idle_speed: float = 60.0
## Direction used only if no owner_player is available to read facing
## from (e.g. testing this scene standalone in the editor).
@export var fallback_direction: Vector2 = Vector2.RIGHT
@export var apply_gravity: bool = false

@export_group("Flight — Deflect & Return")
## Whether the spawning owner can hit this projectile at all to launch
## it out of its idle cruise. Master switch — if false, returnable
## below has no effect either.
@export var deflectable: bool = true
## Whether, once launched, whoever does NOT currently own it can hit it
## back — flipping ownership and sending it the other way.
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

@export_group("Lifetime / Safety")
@export var max_lifetime: float = 6.0
@export var max_travel_distance: float = 3000.0

@export_group("Visual")
## Only used if no textured Sprite2D child is present.
@export var placeholder_radius: float = 16.0
@export var placeholder_color: Color = Color(1.0, 0.85, 0.2)

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

var owner_player: Player = null
var target_player: Player = null

var velocity: Vector2 = Vector2.ZERO

var _facing_dir: float = 1.0
var _launched: bool = false
var _last_launching_move: MoveData = null
var _spawn_position: Vector2
var _life: float = 0.0

# True while a hurtbox contact is being held pending because the target
# was already mid-attack when contact was detected — gives them a real
# chance to deflect instead of eating a hit their own swing was about
# to counter. Held for as long as target_player.current_move stays
# non-null; deflect is checked first every frame, so the moment their
# hitbox goes active it wins before this ever resolves as damage.
var _pending_hit: bool = false
# Safety net only, in case current_move somehow never clears.
var _pending_hit_timer: float = 0.0
const PENDING_HIT_MAX_HOLD: float = 1.0


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
		_dbg("[SETUP] no target_player found — this projectile can still fly and be deflected, but will never resolve a hit.")
	if not impact_move_data:
		_dbg("[SETUP] no impact_move_data assigned — reaching a target will just despawn this with no damage.")

	queue_redraw()


func _physics_process(delta: float) -> void:
	_life += delta
	if _life >= max_lifetime:
		_dbg("[LIFETIME] max_lifetime reached, freeing")
		queue_free()
		return

	var deflected_this_frame: bool = _check_deflect()

	if apply_gravity:
		velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, idle_speed * _facing_dir, deceleration * delta)

	global_position += velocity * delta

	if global_position.distance_to(_spawn_position) >= max_travel_distance:
		_dbg("[LIFETIME] max_travel_distance reached, freeing")
		queue_free()
		return

	# A deflect this frame is fully resolved above — never also let the
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

	if _target_hurtbox_overlapping():
		if target_player and target_player.current_move:
			_pending_hit = true
			_pending_hit_timer = 0.0
		else:
			_resolve_target_hit()


# Phase-gated: before it's ever been launched, only the spawning owner
# can hit it. Once launched, only whoever does NOT currently own it is
# eligible — that's what makes a "hit it back" volley alternate sides.
# Returns true if a deflect actually happened this frame.
func _check_deflect() -> bool:
	if not deflectable:
		return false
	if not _launched:
		return _try_deflect(owner_player)
	elif returnable:
		return _try_deflect(target_player)
	return false


# Mirrors Player._check_hit(): only counts as a hit during the hitting
# player's actual active frames, read straight off their own
# current_move.
func _try_deflect(hitting_player: Player) -> bool:
	if not hitting_player:
		return false

	var move := hitting_player.current_move
	if not move or move == _last_launching_move:
		return false

	var hitbox_shape: CollisionShape2D = hitting_player.get_node_or_null("Hitbox/MainHitbox")
	if not hitbox_shape or hitbox_shape.disabled:
		return false

	var hitbox_area: Area2D = hitting_player.get_node_or_null("Hitbox")
	if not hitbox_area or hitbox_area not in get_overlapping_areas():
		return false

	_apply_deflect(hitting_player, move)
	return true


func _apply_deflect(hitting_player: Player, move: MoveData) -> void:
	var was_return: bool = _launched and hitting_player != owner_player
	if was_return:
		var previous_owner := owner_player
		owner_player = hitting_player
		target_player = previous_owner
		owner_player_id = hitting_player.player_id

	# Added, not replaced — a returned hit stacks its knock_back on top
	# of whatever speed the projectile already had.
	var current_speed: float = absf(velocity.x)
	var added_speed: float = absf(move.knock_back) * launch_speed_multiplier
	var new_speed: float = maxf(current_speed + added_speed, min_launch_speed)
	if max_launch_speed > 0.0:
		new_speed = minf(new_speed, max_launch_speed)

	_facing_dir = 1.0 if hitting_player.facing_right else -1.0
	velocity.x = new_speed * _facing_dir

	_launched = true
	_last_launching_move = move

	_dbg("[DEFLECT] %s | player=%d move='%s' knock_back=%.1f | %.1f -> %.1f" % [
		"RETURNED (now player %d's)" % hitting_player.player_id if was_return else "LAUNCHED",
		hitting_player.player_id, move.move_name, move.knock_back, current_speed, new_speed
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
		_dbg("[IMPACT] reached target with no impact_move_data, despawning without a hit")
		queue_free()
		return

	var was_blocked: bool = target_player.take_hit(impact_move_data, self)

	if owner_player:
		EventBus.player_hit_landed.emit(owner_player.player_id, impact_move_data.move_name, was_blocked)
	if emit_hit_effects:
		EventBus.hit_confirmed.emit(global_position, impact_move_data, self, target_player, was_blocked)

	_dbg("[IMPACT] hit target | blocked=%s damage=%.1f" % [was_blocked, impact_move_data.damage])

	if (was_blocked and destroy_on_block) or (not was_blocked and destroy_on_hit):
		queue_free()


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


func _draw() -> void:
	var sprite := get_node_or_null("Sprite")
	if sprite and sprite is Sprite2D and sprite.texture:
		return
	draw_circle(Vector2.ZERO, placeholder_radius, placeholder_color)


func _dbg(msg: String) -> void:
	if debug:
		print("[Projectile] ", msg)
