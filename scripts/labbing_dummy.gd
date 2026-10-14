extends CharacterBody2D
class_name Dummy

# ──────────────────────────────────────────────────────────────────
#  Dummy (Practice Range training horse)
#
#  Stands still and gets hit. What makes it useful is that it blocks like a
#  player does: it can be doing nothing, holding a crouch block, or holding a
#  standing block, and an attack only lands if it beats whichever of those is
#  up. Overheads beat a crouch block, lows beat a stand block, mids are
#  blocked by either - the same rule the Player uses in
#  _block_posture_beats_hit_level(), so practice matches the real thing.
#
#  It can cycle through those three states on a timer (so you can practise
#  reacting to it) or sit in one state you pick from the practice menu. Both
#  are exported and driven from that menu.
#
#  Debug readout is scene nodes, not a HUD: a state label above it, and a
#  floating label per hit showing the move's hit level, whether it was
#  blocked, and the damage.

## Which of the three blocking states it holds.
enum BlockState { NONE, CROUCH, STAND }

## The horse sheet's rest pose. Its only other animation is "take_hit".
const REST_ANIM := "default"

## Text colour for a hit the dummy blocked. Put on the label rather than on the
## plaque, so the plaque art keeps its own tint. cbdbfc is the project's blue.
const BLOCKED_READOUT_COLOUR := Color(0.79607844, 0.85882354, 0.9882353, 1.0)

@onready var hurtbox_shape: RectangleShape2D = $Hurtbox/hurtbox.shape
@onready var hitbox_shape: RectangleShape2D = $collision_box.shape
@onready var horse_sprite: AnimatedSprite2D = $horse_sprite

## Scene-wired readouts. The float readout is a hidden template: every hit
## duplicates it, so its font, size and outline stay tuned in the scene. It is
## a bare label on purpose - a temporary number over the horse reads better with
## no frame behind it, and the frame art is spent on the running total instead.
@export var state_label: Label
@export var float_label_template: Label

## The running total: a stationary framed readout above the horse, as its own
## scene node, plus the timer that clears it once the hits stop.
@export var total_damage_display: Node2D
@export var total_damage_label: Label
@export var total_damage_timer: Timer

@export_group("Blocking")
## Cycle through the three block states on a timer. Off means it holds
## fixed_block_state instead - which is still the offline path if someone
## unticks this in the Inspector, but the practice menu no longer offers a
## toggle, so a dummy left off would sit in one state forever.
@export var cycle_block_states: bool = true
## The state it holds while cycle_block_states is off.
@export var fixed_block_state: BlockState = BlockState.NONE
## How long each state is held while cycling.
@export var block_cycle_seconds: float = 1.6
## Where the cycle starts when cycling is switched on.
@export var cycle_start_state: BlockState = BlockState.NONE

@export_group("Blocking visuals")
## Barrier timing, matching PlayerVisuals: the start frames run at
## block_warning_frame_duration, the last of them holds while the block is up,
## and the end frame plays once on release before the barrier hides.
@export var block_warning_frame_duration: float = 0.04
@export var block_warning_start_frames: PackedInt32Array = [0, 1]
@export var block_warning_end_frame: int = 2
## The same barrier sprites the Player shows while holding a block, so the
## dummy signals blocking exactly the way a player does. Its own colour is
## never used to communicate state.
@export var mid_block_barrier: Sprite2D
@export var low_block_barrier: Sprite2D
## Brief brightening when damage lands. Feedback for being hit, not a state.
@export var hit_flash_colour: Color = Color(1.7, 1.7, 1.7, 1.0)
@export var hit_flash_seconds: float = 0.12

@export_group("Debug readout")
## Seconds a floating hit label stays up.
@export var float_label_duration: float = 1.15
## How far it drifts upwards over that time.
@export var float_label_rise: float = 46.0
## Where a hit's readout appears, relative to the dummy, in screen pixels.
## Offsets the number up over the horse's body; the readout itself is never
## attached to the player, and the stationary total display sits above where
## these fade out.
@export var float_label_offset: Vector2 = Vector2(0.0, -20.0)
## Whether the state label is shown at all.
@export var show_state_label: bool = true

## Ids here follow the same 1/2 convention as Player: the dummy is "player 2"
## of the lab. It used to be 3, which several systems (ComboManager's
## _other_player_id, anything indexing by player_id) do not understand.
@export var player_id: int = 2

@export var debug = true

var opponent = null
var current_move: MoveData = null
var hit_connected: bool = false
var _hit_registered_this_activation: bool = false
var pushback_velocity_x: float = 0.0
var damage_reduction: float = 0.0
var knockback_reduction: float = 0.0
var was_crouching = false

var block_state: BlockState = BlockState.NONE
var total_damage_taken: float = 0.0

var _cycle_timer: float = 0.0

# Barrier animation state, mirroring PlayerVisuals' block warning phases.
enum BarrierPhase { NONE, START, HOLD, END }
var _barrier_phase: BarrierPhase = BarrierPhase.NONE
var _barrier_frame_index: int = 0
var _barrier_timer: float = 0.0
var _barrier_is_crouching: bool = false
# True while the horse's take_hit animation runs, so nothing overwrites it.
var _playing_hit: bool = false


func _ready() -> void:
	base_hurtbox_size = hurtbox_shape.size
	base_hurtbox_position = $Hurtbox.position

	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player:
			opponent = p
			break
	if not opponent:
		push_warning("[SETUP] No opponent found in 'players' group.")

	block_state = cycle_start_state
	_apply_state_visuals()
	_dbg("[color=green][HORSE] Registered opponent as: %s" % opponent)


var base_hurtbox_size: Vector2
var base_hurtbox_position: Vector2


func _process(delta: float) -> void:
	_update_block_warning(delta)
	if not cycle_block_states:
		return
	_cycle_timer += delta
	if _cycle_timer < block_cycle_seconds:
		return
	_cycle_timer = 0.0
	set_block_state((block_state + 1) % 3)


## Called by the practice menu (and by the cycle above). Everything it needs is
## a real node or an exported value, so the look is tuned in the scene.
func set_block_state(new_state: int) -> void:
	if new_state == block_state:
		return
	block_state = new_state
	_apply_state_visuals()


func set_cycling(enabled: bool) -> void:
	cycle_block_states = enabled
	_cycle_timer = 0.0
	if enabled:
		_apply_state_visuals()


func set_fixed_state(new_state: int) -> void:
	fixed_block_state = new_state
	if not cycle_block_states:
		set_block_state(new_state)


func state_name() -> String:
	match block_state:
		BlockState.CROUCH:
			return "CROUCH BLOCK"
		BlockState.STAND:
			return "STAND BLOCK"
		_:
			return "NOT BLOCKING"


# ── Blocking rules ──
# Mirrors Player._block_posture_beats_hit_level(): an overhead is blocked
# standing only, a low is blocked crouching only, a mid is blocked by either.
# Not blocking blocks nothing at all.

func _state_blocks_hit_level(hit_level: MoveData.HitLevel) -> bool:
	match block_state:
		BlockState.CROUCH:
			return hit_level != MoveData.HitLevel.OVERHEAD
		BlockState.STAND:
			return hit_level != MoveData.HitLevel.LOW
		_:
			return false


func _apply_state_visuals() -> void:
	_refresh_state_label()

	# Same barrier selection PlayerVisuals.update_block_warning() makes: the
	# low barrier while crouch blocking, the mid one while standing.
	if mid_block_barrier:
		mid_block_barrier.visible = block_state == BlockState.STAND
	if low_block_barrier:
		low_block_barrier.visible = block_state == BlockState.CROUCH

	if horse_sprite == null:
		return
	var wanted := ""
	match block_state:
		BlockState.CROUCH:
			wanted = "block_crouch"
		BlockState.STAND:
			wanted = "block_stand"
		_:
			wanted = REST_ANIM
	# The horse sheet carries "default" (its rest pose) and "take_hit" only,
	# so "default" is what every state falls back to. Looking for "idle" here
	# meant nothing was ever played and a hit left the horse frozen in its
	# take_hit pose.
	if _has_animation(wanted):
		horse_sprite.play(wanted)
	elif _has_animation(REST_ANIM):
		horse_sprite.play(REST_ANIM)


# The barrier sequence, lifted from PlayerVisuals.update_block_warning() so the
# dummy's barriers animate exactly like a player's: run the start frames, hold
# the last one while the block is up, play the end frame once on release, hide.
func _update_block_warning(delta: float) -> void:
	var should_show := block_state != BlockState.NONE
	var is_crouching := block_state == BlockState.CROUCH

	if _barrier_phase != BarrierPhase.NONE and is_crouching != _barrier_is_crouching:
		_close_barrier()

	var barrier := _active_barrier(is_crouching)
	var other := _active_barrier(not is_crouching)
	if other:
		other.visible = false
	if barrier == null:
		_barrier_phase = BarrierPhase.NONE
		return

	if should_show and _barrier_phase == BarrierPhase.NONE:
		_barrier_phase = BarrierPhase.START
		_barrier_frame_index = 0
		_barrier_timer = 0.0
		_barrier_is_crouching = is_crouching
		barrier.visible = true
		barrier.frame = block_warning_start_frames[0]
	elif should_show and _barrier_phase == BarrierPhase.START:
		barrier.visible = true
		_barrier_timer += delta
		if _barrier_timer >= block_warning_frame_duration:
			_barrier_timer = 0.0
			_barrier_frame_index += 1
			if _barrier_frame_index >= block_warning_start_frames.size():
				_barrier_phase = BarrierPhase.HOLD
				barrier.frame = block_warning_start_frames[block_warning_start_frames.size() - 1]
			else:
				barrier.frame = block_warning_start_frames[_barrier_frame_index]
	elif should_show:
		barrier.visible = true
		barrier.frame = block_warning_start_frames[block_warning_start_frames.size() - 1]
	elif _barrier_phase != BarrierPhase.NONE:
		if _barrier_phase != BarrierPhase.END:
			_barrier_phase = BarrierPhase.END
			_barrier_timer = 0.0
			barrier.frame = block_warning_end_frame
			barrier.visible = true
		_barrier_timer += delta
		if _barrier_timer >= block_warning_frame_duration:
			_close_barrier()


func _close_barrier() -> void:
	_barrier_phase = BarrierPhase.NONE
	_barrier_is_crouching = false
	if mid_block_barrier:
		mid_block_barrier.visible = false
	if low_block_barrier:
		low_block_barrier.visible = false


func _active_barrier(is_crouching: bool) -> Sprite2D:
	return low_block_barrier if is_crouching else mid_block_barrier


func _refresh_state_label() -> void:
	if state_label == null:
		return
	state_label.text = "BLOCK: %s%s" % [state_name(), "  (cycling)" if cycle_block_states else ""]
	state_label.visible = show_state_label


# Named entry point for "put the horse into its current state's pose". Used when
# a hit animation finishes, so it returns to the right pose without the caller
# having to know anything about the state machine.
func _play_state_animation() -> void:
	_apply_state_visuals()


func _has_animation(anim_name: String) -> bool:
	return horse_sprite != null and horse_sprite.sprite_frames != null \
		and horse_sprite.sprite_frames.has_animation(anim_name)


func _dbg(msg: String) -> void:
	if debug:
		print_rich("[P%d] %s" % [player_id, msg])


# ── Taking hits ──

func take_hit(move_data: MoveData, attacker: Node2D) -> bool:
	was_crouching = (block_state == BlockState.CROUCH)
	var blocked := _state_blocks_hit_level(move_data.hit_level)

	if blocked:
		_resolve_block(move_data, attacker)
		_show_hit_readout(move_data, true, 0.0)
		return true

	_hit_anim_resolve()
	return _resolve_hit(move_data, attacker, was_crouching)


func _resolve_block(move_data: MoveData, attacker: Node2D) -> void:
	pushback_velocity_x = _direction_away_from(attacker) * move_data.block_knock_back
	_dbg("[color=cyan][BLOCK] %s blocked by %s" % [move_data.move_name, state_name()])
	EventBus.player_hit_landed.emit(player_id, move_data.move_name, true)
	EventBus.hit_confirmed.emit(global_position, move_data, attacker, self, true)


func _resolve_hit(move_data: MoveData, attacker: Node2D, _was_crouching: bool) -> bool:
	# Same damage maths as Player._resolve_hit so the numbers mean the same
	# thing: move damage + the attacker's flat bonus - this dummy's reduction,
	# never below zero.
	var attacker_bonus: float = 0.0
	var player_attacker := attacker as Player
	if player_attacker:
		attacker_bonus = player_attacker.damage_dealt_bonus
	var final_damage: float = max(move_data.damage + attacker_bonus - damage_reduction, 0.0)
	# Through the running-total path rather than a bare += : that is what shows
	# the display and restarts its hold. A blocked hit never reaches here, so it
	# never counts toward the total.
	_add_total_damage(final_damage)

	var move_is_launcher = move_data.is_launcher or move_data.launcher_strength > 0.0
	var effective_knockback: float = max(move_data.knock_back - knockback_reduction, 0.0)
	pushback_velocity_x = _direction_away_from(attacker) * effective_knockback
	if move_is_launcher:
		velocity.y = -move_data.launcher_strength

	_dbg("[color=cyan][DAMAGE] %s | base %.1f + bonus %.1f - reduction %.1f = %.1f | total %.1f" % [
		move_data.move_name, move_data.damage, attacker_bonus, damage_reduction, final_damage, total_damage_taken
	])
	EventBus.player_hit_landed.emit(player_id, move_data.move_name, false)
	EventBus.hit_confirmed.emit(global_position, move_data, attacker, self, false)
	EventBus.npc_cheer.emit()
	flash_on_damage()
	_show_hit_readout(move_data, false, final_damage)
	return false


## Brighter for a moment when damage lands. Separate from the barrier sprites:
## the horse itself never changes colour to show a block state.
func flash_on_damage() -> void:
	if horse_sprite == null:
		return
	horse_sprite.modulate = hit_flash_colour
	var tween := create_tween()
	tween.tween_property(horse_sprite, "modulate", Color.WHITE, hit_flash_seconds)


func _apply_pushback() -> void:
	if not current_move or not opponent:
		return
	pushback_velocity_x = _direction_away_from(opponent) * current_move.pushback_on_block


func _direction_away_from(other: Node2D) -> float:
	if other == null:
		return 1.0
	return -1.0 if other.global_position.x > global_position.x else 1.0


func _hit_anim_resolve() -> void:
	if not _has_animation("take_hit"):
		return
	# Held for the whole animation so no rest pose is played over it.
	_playing_hit = true
	horse_sprite.play("take_hit")
	await horse_sprite.animation_finished
	_playing_hit = false
	_play_state_animation()


# ── Debug readout ──
# One floating plaque per hit: what the move's hit level was, whether the dummy
# blocked it, and the damage. Built by duplicating the hidden template node in
# the scene, so the plaque art behind the number, its font, its size and its
# outline all stay Inspector-editable rather than being built in code.

func _show_hit_readout(move_data: MoveData, blocked: bool, damage: float) -> void:
	# Two lines so the readout fills the plaque rather than overhanging it: the
	# hit level on top, the outcome underneath. The level matters to practice -
	# it is what the dummy's cycling block state is being tested against.
	var text := "%s\n%s" % [
		hit_level_name(move_data.hit_level),
		"BLOCKED" if blocked else "%.1f" % damage,
	]
	_spawn_float_label(text, blocked)
	# Only the readout refreshes here, never _apply_state_visuals(): that plays
	# the rest pose, which was cancelling the hit animation on the same frame
	# take_hit had just started it.
	_dbg("[READOUT] %s" % text.replace("\n", " - "))


func hit_level_name(hit_level: MoveData.HitLevel) -> String:
	match hit_level:
		MoveData.HitLevel.OVERHEAD:
			return "Overhead"
		MoveData.HitLevel.LOW:
			return "Low"
		_:
			return "Mid"


func _spawn_float_label(text: String, blocked: bool) -> void:
	if float_label_template == null or not is_inside_tree():
		return
	var label := float_label_template.duplicate() as Label
	if label == null:
		return
	float_label_template.get_parent().add_child(label)
	label.text = text
	# White for a hit that landed, light blue for one that was blocked: the
	# palette is white, blue and black, and the outcome is in the text anyway.
	label.modulate = BLOCKED_READOUT_COLOUR if blocked else Color.WHITE
	# The template is hidden in the scene so it never draws itself; the duplicate
	# inherits that, so it has to be shown explicitly.
	label.visible = true
	label.global_position = _readout_spawn_position()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "global_position:y", label.global_position.y - float_label_rise, float_label_duration)
	tween.tween_property(label, "modulate:a", 0.0, float_label_duration)
	tween.chain().tween_callback(label.queue_free)


# The readout is parented to the DamageNumbers CanvasLayer, which is screen
# space, while this dummy lives in world space. Converting through the camera
# puts the number over the horse rather than at a fixed screen offset that
# drifts the moment the camera follows the player. It is placed once, at spawn,
# and the float is its own drift: nothing here follows anything.
func _readout_spawn_position() -> Vector2:
	var screen_position := get_viewport().get_canvas_transform() * global_position
	return screen_position + float_label_offset


# ── Running total ──
# A separate display from the per-hit numbers: it stays where it is above the
# horse, counts every point of damage dealt, and clears itself five seconds
# after the last hit. The hold lives on a Timer node in the scene, so its length
# is Inspector-editable rather than a number buried in code, and restarting the
# timer on every hit is what makes the five seconds "since the last hit" rather
# than "since the first".

func _add_total_damage(amount: float) -> void:
	total_damage_taken += amount
	if total_damage_display:
		total_damage_display.visible = true
	_refresh_total_label()
	if total_damage_timer:
		total_damage_timer.start()


func _on_total_damage_timeout() -> void:
	total_damage_taken = 0.0
	_refresh_total_label()
	if total_damage_display:
		total_damage_display.visible = false


func _refresh_total_label() -> void:
	if total_damage_label == null:
		return
	total_damage_label.text = "TOTAL DAMAGE\n%.1f" % total_damage_taken
