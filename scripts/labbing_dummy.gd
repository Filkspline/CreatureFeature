extends CharacterBody2D
class_name Dummy

@onready var hurtbox_shape: RectangleShape2D = $Hurtbox/hurtbox.shape
@onready var hitbox_shape: RectangleShape2D = $collision_box.shape
@onready var horse_sprite: AnimatedSprite2D = $horse_sprite
var base_hurtbox_size: Vector2
var base_hurtbox_position: Vector2

var opponent = null

var current_move: MoveData = null

var hit_connected: bool = false

var _hit_registered_this_activation: bool = false

var pushback_velocity_x: float = 0.0

var damage_reduction: float = 0.0

var knockback_reduction: float = 0.0

var was_crouching = false

@export var debug = true
@export var player_id = 3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	base_hurtbox_size = hurtbox_shape.size
	base_hurtbox_position = $Hurtbox.position
	
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and (p is Player or p is Dummy):
			opponent = p
			break
	if not opponent:
		push_warning("[SETUP] No opponent found in 'players' group.")
	
	_dbg("[color=green][HORSE] Registered opponent as: %s" % opponent)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#await horse_sprite.animation_finished
	#horse_sprite.play("default")

func _dbg(msg: String) -> void:
	if debug:
		print_rich("[P%d] %s" % [player_id, msg])


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
			
			_dbg("[color=yellow][HORSE] Taking damage")
			
			#if hornet_selected == true:
			#	_dbg("[color=yellow][HORNET] Hornet activated")
			#	damage_dealt_bonus += _effect_hornet()
			
			EventBus.npc_cheer.emit() # Just here to call for the npc's to cheer when a player is hit
			
			if was_blocked:
				_apply_pushback()
			return

func _apply_pushback() -> void:
	if not current_move or not opponent:
		return
	pushback_velocity_x = _direction_away_from(opponent) * current_move.pushback_on_block
	
func _direction_away_from(other: Node2D) -> float:
	return -1.0 if other.global_position.x > global_position.x else 1.0


func take_hit(move_data: MoveData, attacker: Node2D) -> bool:
	#var was_crouching = (crouch_phase != CrouchPhase.NONE)
	# Must read block readiness before crouch_phase gets reset below,
	# since _is_block_ready() checks crouch_phase live and would
	# otherwise always see NONE and fall through to requiring back-hold.
	#var can_block_right_now = state == State.NEUTRAL or state == State.BLOCKSTUN
	#var block_ready = can_block_right_now and _is_block_ready() and _block_posture_beats_hit_level(move_data.hit_level, was_crouching)

	#crouch_phase = CrouchPhase.NONE
	#wants_to_crouch = false
	#is_landing = false

	#_disable_combat_shapes_on_hit()

	#if block_ready:
	#	_resolve_block(move_data, attacker, was_crouching)
	#	return true
	
	_hit_anim_resolve()
	_resolve_hit(move_data, attacker, was_crouching)
	return false


func _resolve_hit(move_data: MoveData, attacker: Node2D, was_crouching: bool) -> void:
	
	#if armour_plating_selected == true:
	#	if armour_plating_active == true:
	#		damage_reduction = _effect_armour_plating()
	#		_dbg("[color=yellow][ARMOUR PLATING] End damage reduction: %s" % damage_reduction)
	#	else:
	#		damage_reduction = 0
	
	
	# Damage order (designer-confirmed): base move damage + attacker's flat
	# bonus, then subtract this defender's flat reduction, clamped to >= 0
	# so a hit can be reduced to zero but never heal. The bonus is only read
	# when the attacker is a Player (melee); projectile/test hits pass a
	# non-Player attacker and simply add no bonus.
	var attacker_bonus: float = 0.0
	var player_attacker := attacker as Player
	if player_attacker:
		attacker_bonus = player_attacker.damage_dealt_bonus
	var final_damage: float = move_data.damage + attacker_bonus - damage_reduction
	final_damage = max(final_damage, 0.0)
	# Combo decay: consecutive hits on this defender deal progressively less.
	var combo_scale: float = ComboManager.get_combo_damage_scale(player_id)
	final_damage = final_damage# * combo_scale
	
	

	#var health_before: float = current_health
	#current_health = max(current_health - final_damage, 0.0)
	#EventBus.player_health_changed.emit(player_id, current_health)
	_dbg("[color=cyan][DAMAGE] base %.1f + bonus %.1f - reduction %.1f = %.1f (combo x%.2f)[/color]" % [
		move_data.damage, attacker_bonus, damage_reduction, final_damage, combo_scale
	])

	#if current_health <= 0.0 and not is_defeated:
	#	is_defeated = true
	#	EventBus.player_defeated.emit(player_id)

	# is_launcher is treated as true if EITHER the checkbox is on OR
	# launcher_strength is non-zero. This exists because "set
	# launcher_strength, forget to also tick is_launcher" is a really
	# easy mistake to make in the inspector; launcher_strength is what
	# actually sets the upward velocity below.
	var move_is_launcher = move_data.is_launcher or move_data.launcher_strength > 0.0
	# Air hit = launcher OR hit taken while already airborne. Both use the
	# airhit reaction and recover through normal hitstun.
	var is_air_hit: bool = move_is_launcher or not is_on_floor()

	# Knockback reduction is flat armor: subtract it from the move's
	# knockback, clamped to >= 0 so it can't invert into a pull toward the attacker.
	var effective_knockback: float = max(move_data.knock_back - knockback_reduction, 0.0)
	pushback_velocity_x = _direction_away_from(attacker) * effective_knockback
	if move_is_launcher:
		velocity.y = -move_data.launcher_strength

	#_dbg("[RESOLVE HIT] '%s' is_launcher=%s launcher_strength=%.1f -> move_is_launcher=%s velocity.y=%.1f" % [
	#	move_data.move_name, move_data.is_launcher, move_data.launcher_strength, move_is_launcher, velocity.y
	#])

	#var hitstun_frames = move_data.hitstun
	#var reaction_anim := "airhit" if is_air_hit else ("crouch_hit" if was_crouching else "mid_hit")
	#hitstun_frames = max(hitstun_frames, _min_visible_stun_frames(reaction_anim))

	#stun_timer = hitstun_frames / 60.0
	#stun_just_started = true
	#state = State.HITSTUN

	#call_deferred("_apply_hit_reaction_visuals", was_crouching, is_air_hit)


func _hit_anim_resolve() -> void:
	horse_sprite.play("take_hit")
	await horse_sprite.animation_finished
