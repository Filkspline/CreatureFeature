extends Node2D
class_name PlayerVisuals

# ──────────────────────────────────────────────────────────────────
#  PlayerVisuals
#
#  Lives on the "Sprites" Node2D under Player. Owns every Sprite2D,
#  drives the AnimationPlayer (which stays parented under Player,
#  not here, since its animation tracks touch Hitbox/Hurtbox/Player
#  directly), and tracks "what's currently showing".
#
#  Player tells this node WHAT happened (walking, jumping, got hit...)
#  by calling the play_*() methods below. This node decides HOW that
#  looks (which sprite, which animation, frame-stepping the block
#  warning, the squash/stretch bounce, etc). Player never touches a
#  Sprite2D or the AnimationPlayer directly for presentation.
# ──────────────────────────────────────────────────────────────────

# Fires after the AnimationPlayer's own animation_finished, once this
# node has done its own housekeeping (pausing hold-on-finish anims).
# Player listens to this to react with game-logic (crouch transitions etc).
signal animation_finished(anim_name: String)

# ── Debug ────────────────────────────────────────────────────────
@export var debug: bool = true

# ── Animations that should NOT loop (paused on their last frame) ──
@export var hold_on_finish_anims: Array[String] = [
	"jump_rise", "jump_peak", "jump_land",
	"crouch_down", "crouch_up",
	"crouch_hit", "crouch_hit_2", "mid_hit", "mid_hit_2", "mid_hit_3",
	"airhit"
]

# ── Animations that should loop ───────────────────────────────────
@export var looping_anims: Array[String] = [
	"block_idle", "crouch_block_idle", "crouch_idle",
	"idle", "walk_forward", "walk_backward"
]

# ── Squash & stretch "bounce" on animation start ──────────────────
@export var bounce_squash_scale: Vector2 = Vector2(1.2, 0.8)
@export var bounce_normal_scale: Vector2 = Vector2(1.0, 1.0)
@export var bounce_duration: float = 0.15
@export var bounce_excluded_anims: Array[String] = ["crouch_down", "crouch_idle","jump_land","SA","jump_peak"]

# ── Block warning (manual frame-stepping, no Animation resource) ──
@export var block_warning_frame_duration: float = 0.04
@export var block_warning_start_frames: PackedInt32Array = [0, 1]
@export var block_warning_end_frame: int = 2

# ── Dash afterimage trail (ghost copies) ────────────────────────────
# Spawned at runtime rather than authored in the scene, the same way the
# hit particles are: one instance of dash_afterimage_scene per spawn,
# parented into the effects layer, fading out and freeing itself. How a
# ghost looks lives on that scene; the emission rate and the cap on how
# many may exist are here.
## Ghost scene instantiated per afterimage. Defaults to the dash afterimage
## effect; point it at another scene to reuse this spawn path with a
## different look.
@export var dash_afterimage_scene : PackedScene = preload("res://scenes/dash_afterimage.tscn")
## Seconds between ghosts while a dash move is active. Lower is a denser
## trail; 0.0 spawns one every frame, up to the cap below.
@export var dash_afterimage_interval : float = 0.05
## Most ghosts one player may have alive at once. Going over frees the
## oldest early, which is what stops a long dash from stacking up into a
## solid wall of copies.
@export var dash_afterimage_max : int = 6

enum BlockWarningPhase { NONE, START, HOLD, END }

@onready var idle_sprite: Sprite2D = $Idle
@onready var walk_backward_sprite: Sprite2D = $WalkBackward
@onready var walk_forward_sprite: Sprite2D = $WalkForward
@onready var jump_sprite: Sprite2D = $Jump
@onready var crouch_sprite: Sprite2D = $Crouch
@onready var mid_block_warning: Sprite2D = $MidBlockWarning
@onready var low_block_warning: Sprite2D = $LowBlockWarning
@onready var block_idle_sprite: Sprite2D = $BlockIdle
@onready var crouch_block_idle_sprite: Sprite2D = $CrouchBlockIdle
@onready var crouch_hit_sprite: Sprite2D = $CrouchHit
@onready var crouch_hit2_sprite: Sprite2D = $CrouchHit2
@onready var mid_hit_sprite: Sprite2D = $MidHit
@onready var mid_hit2_sprite: Sprite2D = $MidHit2
@onready var mid_hit3_sprite: Sprite2D = $MidHit3
@onready var airhit_sprite: Sprite2D = $Airhit

# Attack sprites are NOT fixed @onready vars — they're looked up by move
# name (e.g. "N5", "S6") when setup() runs, so adding a new move later is
# just: assign the MoveData on Player + add a same-named Sprite2D child
# here. No script changes, and a move with no sprite yet just shows
# nothing instead of erroring.
var attack_sprites: Dictionary = {}

var animation_player: AnimationPlayer
var active_sprite: Sprite2D = null
var bounce_tween: Tween = null
var current_anim: String = ""

var block_warning_phase: int = BlockWarningPhase.NONE
var block_warning_frame_index: int = 0
var block_warning_timer: float = 0.0
var block_warning_is_crouching: bool = false
# Dash trail state. Everything is per instance, so both players can dash at
# the same time and each one keeps its own timer and ghost list.
var _afterimages_active: bool = false
var _afterimage_timer: float = 0.0
var _afterimages: Array[Node] = []
# Hit reaction variety tracking (per player instance).
var _last_mid_hit_index: int = -1  # last mid_hit variant played, avoids a repeat
var _crouch_hit_alternate: bool = false  # flips between crouch_hit and crouch_hit_2


func _dbg(msg: String) -> void:
	if debug:
		print(msg)


# ── Setup, called once by Player._ready() ─────────────────────────
# move_names should be Player.all_moves.keys() — only moves that actually
# have a MoveData assigned get a sprite lookup, so nothing breaks if a
# future move (e.g. S6) is assigned before its sprite exists, or vice versa.
func setup(anim_player: AnimationPlayer, move_names: Array = []) -> void:
	animation_player = anim_player

	attack_sprites.clear()
	for move_name in move_names:
		var node = get_node_or_null(String(move_name))
		if node and node is Sprite2D:
			node.visible = false
			attack_sprites[move_name] = node
		else:
			_dbg("[SPRITES] no Sprite2D child named '%s' — that move won't show a sprite until one's added" % move_name)

	# Blocking sprites off
	mid_block_warning.visible = false
	low_block_warning.visible = false
	block_idle_sprite.visible = false
	crouch_block_idle_sprite.visible = false
	# Hit-reaction sprites off
	crouch_hit_sprite.visible = false
	crouch_hit2_sprite.visible = false
	mid_hit_sprite.visible = false
	mid_hit2_sprite.visible = false
	mid_hit3_sprite.visible = false
	airhit_sprite.visible = false

	# Configure loop modes for all animations
	for anim_name in animation_player.get_animation_list():
		var anim = animation_player.get_animation(anim_name)
		if anim:
			if anim_name in hold_on_finish_anims:
				anim.loop_mode = Animation.LOOP_NONE
			elif anim_name in looping_anims:
				anim.loop_mode = Animation.LOOP_LINEAR
			#_dbg("[ANIM SETUP] '%s' -> loop_mode=%s length=%.4f" % [anim_name, anim.loop_mode, anim.length])
		else:
			push_warning("[ANIM SETUP] '%s' returned null Animation resource!" % anim_name)

	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.animation_started.connect(_on_animation_started)

	# Reset everything to default frame states
	animation_player.play("RESET")
	animation_player.seek(0.0, true)

func set_facing(facing_right: bool) -> void:
	scale.x = 1.0 if facing_right else -1.0

func get_current_anim() -> String:
	return current_anim


# The sprite actually on screen right now, or null if nothing is showing.
# Attacks are shown through attack_sprites (keyed by animation_name) and
# never go through play_anim(), so active_sprite alone would be stale
# during a move, and the dash trail copies whatever this returns.
func get_active_sprite() -> Sprite2D:
	# attack_sprites is keyed by animation_name, which is a StringName, while
	# current_anim is a String. String and StringName compare equal with ==
	# but Dictionary lookups hash, and a String key does not find a StringName
	# key, the same trap _try_cancel_gatling documents. Convert, or this
	# silently returns null during every attack.
	var attack_sprite: Sprite2D = attack_sprites.get(StringName(current_anim), null)
	if attack_sprite and attack_sprite.visible:
		return attack_sprite
	if active_sprite and active_sprite.visible:
		return active_sprite
	return null


# ── State-driven playback, called by Player ───────────────────────
func play_idle() -> void:
	play_anim("idle", idle_sprite)


func play_walk(is_forward: bool) -> void:
	if is_forward:
		play_anim("walk_forward", walk_forward_sprite)
	else:
		play_anim("walk_backward", walk_backward_sprite)


func play_jump_rise() -> void:
	play_anim("jump_rise", jump_sprite)


func play_jump_peak() -> void:
	play_anim("jump_peak", jump_sprite)


# Called every frame while falling. Snaps to (and holds) jump_peak's
# last frame instead of playing jump_rise/fall animations we don't have.
func play_jump_fall() -> void:
	if current_anim != "jump_peak":
		_dbg("[JUMP FALL] entering FALL from '%s' -> snapping to held last frame" % current_anim)
		play_anim("jump_peak", jump_sprite, true)
		var anim2 = animation_player.get_animation("jump_peak")
		animation_player.seek(anim2.length - 0.001, true)
		animation_player.pause()
	elif animation_player.is_playing():
		_dbg("[JUMP FALL] jump_peak mid-playback, skipping ahead to held last frame")
		var anim = animation_player.get_animation("jump_peak")
		animation_player.seek(anim.length - 0.001, true)
		animation_player.pause()


func play_jump_land() -> void:
	play_anim("jump_land", jump_sprite, true)


func play_crouch_down() -> void:
	play_anim("crouch_down", crouch_sprite, true)


func play_crouch_idle() -> void:
	play_anim("crouch_idle", crouch_sprite, true)


func play_crouch_up() -> void:
	play_anim("crouch_up", crouch_sprite, true)


func play_block_idle(is_low: bool, force_restart: bool = false) -> void:
	if is_low:
		play_anim("crouch_block_idle", crouch_block_idle_sprite, force_restart)
	else:
		play_anim("block_idle", block_idle_sprite, force_restart)


func play_hit_reaction(was_crouching: bool, is_air_hit: bool = false) -> void:
	if is_air_hit:
		play_anim("airhit", airhit_sprite, true)
	elif was_crouching:
		# Strictly alternate between the two crouch-hit animations.
		_crouch_hit_alternate = not _crouch_hit_alternate
		if _crouch_hit_alternate:
			play_anim("crouch_hit_2", crouch_hit2_sprite, true)
		else:
			play_anim("crouch_hit", crouch_hit_sprite, true)
	else:
		# Random mid-hit, never the same variant twice in a row.
		var index := randi() % 3
		while index == _last_mid_hit_index:
			index = randi() % 3
		_last_mid_hit_index = index
		match index:
			0:
				play_anim("mid_hit", mid_hit_sprite, true)
			1:
				play_anim("mid_hit_2", mid_hit2_sprite, true)
			_:
				play_anim("mid_hit_3", mid_hit3_sprite, true)


func show_attack_sprite(anim_name: StringName) -> void:
	var sprite = attack_sprites.get(anim_name, null)
	if sprite:
		sprite.visible = true
	else:
		_dbg("[SPRITES] show_attack_sprite('%s') — no sprite registered, showing nothing" % String(anim_name))


# Attack animations are driven frame-by-frame by Player (attack_frame),
# so this just starts the AnimationPlayer without the play_anim() skip
# logic getting in the way.
func play_attack_anim(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		animation_player.seek(0, true)
		current_anim = anim_name


# ── Utility: play an animation and show the correct sprite ────────
func play_anim(anim_name: String, sprite_to_show: Sprite2D = null, force_restart: bool = false) -> void:
	if not animation_player.has_animation(anim_name):
		push_error("Animation not found: '%s'" % anim_name)
		return

	# If already on this animation and it's a hold-on-finish, never restart
	if not force_restart and current_anim == anim_name:
		if anim_name in hold_on_finish_anims:
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
	hide_all_sprites()

	# Show the correct sprite if provided
	if sprite_to_show:
		sprite_to_show.visible = true
	active_sprite = sprite_to_show

	current_anim = anim_name
	animation_player.play(anim_name)
	animation_player.seek(0.0, true)  # force immediate apply, avoids one frame of flicker
	if sprite_to_show == crouch_sprite:
		_dbg("[PLAY ANIM] after seek: Crouch.frame=%d" % crouch_sprite.frame)


func hide_all_sprites() -> void:
	idle_sprite.visible = false
	walk_backward_sprite.visible = false
	walk_forward_sprite.visible = false
	jump_sprite.visible = false
	crouch_sprite.visible = false
	hide_attack_sprites()
	block_idle_sprite.visible = false
	crouch_block_idle_sprite.visible = false
	mid_block_warning.visible = false
	low_block_warning.visible = false
	crouch_hit_sprite.visible = false
	crouch_hit2_sprite.visible = false
	mid_hit_sprite.visible = false
	mid_hit2_sprite.visible = false
	mid_hit3_sprite.visible = false
	airhit_sprite.visible = false


func hide_attack_sprites() -> void:
	for sprite in attack_sprites.values():
		sprite.visible = false


func hide_block_sprites() -> void:
	block_idle_sprite.visible = false
	crouch_block_idle_sprite.visible = false


# ── Block warning (manual, no animation available) ────────────────
func update_block_warning(delta: float, should_show: bool, is_crouching: bool) -> void:
	if block_warning_phase != BlockWarningPhase.NONE and is_crouching != block_warning_is_crouching:
		_dbg("[BLOCK WARN] crouch state changed mid-warning (was crouching=%s, now=%s) -> reset" % [block_warning_is_crouching, is_crouching])
		reset_block_warning()

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
		warning_sprite.frame = block_warning_start_frames[0]
		_dbg("[BLOCK WARN] START new warning (crouching=%s)" % is_crouching)

	elif should_show:
		warning_sprite.visible = true
		match block_warning_phase:
			BlockWarningPhase.START:
				block_warning_timer += delta
				if block_warning_timer >= block_warning_frame_duration:
					block_warning_timer = 0.0
					block_warning_frame_index += 1
					if block_warning_frame_index >= block_warning_start_frames.size():
						block_warning_phase = BlockWarningPhase.HOLD
						warning_sprite.frame = block_warning_start_frames[block_warning_start_frames.size() - 1]
						_dbg("[BLOCK WARN] START -> HOLD")
					else:
						warning_sprite.frame = block_warning_start_frames[block_warning_frame_index]

			BlockWarningPhase.HOLD:
				warning_sprite.frame = block_warning_start_frames[block_warning_start_frames.size() - 1]

			BlockWarningPhase.END:
				_dbg("[BLOCK WARN] should_show became true again while still in END -> reset")
				reset_block_warning()

	elif not should_show and block_warning_phase != BlockWarningPhase.NONE:
		if block_warning_phase != BlockWarningPhase.END:
			block_warning_phase = BlockWarningPhase.END
			block_warning_timer = 0.0
			warning_sprite.frame = block_warning_end_frame
			warning_sprite.visible = true
			_dbg("[BLOCK WARN] HOLD -> END")

		block_warning_timer += delta
		if block_warning_timer >= block_warning_frame_duration:
			_dbg("[BLOCK WARN] END finished -> reset")
			reset_block_warning()


func reset_block_warning() -> void:
	mid_block_warning.visible = false
	low_block_warning.visible = false
	block_warning_phase = BlockWarningPhase.NONE
	block_warning_is_crouching = false


# ── Internal AnimationPlayer callbacks ─────────────────────────────
func _on_animation_finished(anim_name: String) -> void:
	# Pause on the last frame for all hold-on-finish animations
	if anim_name in hold_on_finish_anims:
		animation_player.pause()
	animation_finished.emit(anim_name)


# ── Animation bounce ────────────────────────────────────────────────
func _on_animation_started(anim_name: StringName) -> void:
	if String(anim_name) in bounce_excluded_anims:
		return
	if not active_sprite:
		return

	if bounce_tween:
		bounce_tween.kill()

	active_sprite.scale = bounce_squash_scale
	bounce_tween = create_tween()
	bounce_tween.tween_property(active_sprite, "scale", bounce_normal_scale, bounce_duration) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ── Dash afterimage trail ────────────────────────────────────────────
# Player starts and stops this off MoveData.is_dash, so which moves leave a
# trail is data and a new dash move needs no change in here.

func begin_dash_afterimages() -> void:
	_afterimages_active = true
	_afterimage_timer = dash_afterimage_interval
	# One right away, so the first frame of the dash already has a ghost
	# behind it instead of waiting out a whole interval first.
	_spawn_afterimage()


# Stops new ghosts from spawning. The ones already out keep fading on their
# own, which is what leaves a trail hanging behind the player after the dash.
func end_dash_afterimages() -> void:
	_afterimages_active = false


func _process(delta: float) -> void:
	if not _afterimages_active:
		return
	_afterimage_timer -= delta
	if _afterimage_timer > 0.0:
		return
	_afterimage_timer = dash_afterimage_interval
	_spawn_afterimage()


func _spawn_afterimage() -> void:
	if not dash_afterimage_scene:
		return

	var source := get_active_sprite()
	if not source:
		return

	var parent := HitEffectManager.get_effects_parent()
	if not parent:
		return

	var ghost := dash_afterimage_scene.instantiate()
	parent.add_child(ghost)
	# Slot the ghost in directly before its own fighter instead of letting
	# add_child append it last. At the same z_index as the player, tree
	# order is what decides, and appended last would paint the trail over
	# the fighter rather than under him (his attack_z_index covers the
	# ghost for the whole dash). Same sibling-slot trick HitParticle uses
	# for its tear overlay. A scene whose effects layer isn't the player's
	# parent just falls back to plain tree order.
	var owner_player := get_parent()
	if owner_player and ghost.get_parent() == owner_player.get_parent():
		ghost.get_parent().move_child(ghost, owner_player.get_index())

	ghost.appear_from(source)
	_afterimages.append(ghost)
	_prune_afterimages()


# Drops references to ghosts that have already faded out and freed
# themselves, then enforces the alive cap by retiring the oldest survivor.
func _prune_afterimages() -> void:
	var alive: Array[Node] = []
	for ghost in _afterimages:
		if is_instance_valid(ghost):
			alive.append(ghost)
	_afterimages = alive

	while _afterimages.size() > dash_afterimage_max and not _afterimages.is_empty():
		var oldest: Node = _afterimages.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
