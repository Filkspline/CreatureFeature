extends Node
class_name PlayerAudio

# ──────────────────────────────────────────────────────────────────
#  PlayerAudio
#
#  Everything one Player sounds like. Lives on the "Audio" node under
#  Player, beside the Sprites node, and is told WHAT happened by Player the
#  same way PlayerVisuals is: Player never picks a sound or touches an
#  AudioStreamPlayer itself.
#
#  Every stream and its tuning is exported, so both players can be balanced
#  independently here, and a single move can override its own attack sound
#  through its MoveData instead (see the Sound group there).
#
#  One-shot sounds are handed to SfxManager, which owns the pooled playback
#  and the pitch randomisation. The two sounds that have to be stoppable or
#  continuous - the footstep loop and a special's charge-up - own a player
#  each, so cutting them short can never steal a pooled voice from
#  something else.

@export_group("Walk loop")
## Footstep loop. Runs while the walk animation is the one showing, and its
## pitch follows how fast the player is actually moving.
@export var walk_sound: AudioStream = preload("res://assets/soundeffects/WalkSoundRepeatable.mp3")
@export var walk_volume_db: float = 0.0
## The walk speed that walk_base_pitch was tuned against. Set this to
## whatever walk_forward_speed actually is (190 by default on the player),
## then set walk_base_pitch so the loop's steps land on the walk
## animation's steps.
@export var walk_base_move_speed: float = 190.0
## Playback rate at walk_base_move_speed: the loop's own pace, before any
## speed scaling is layered on top of it.
@export var walk_base_pitch: float = 1.0
## How strongly movement speed and animation speed push the loop's pitch,
## as an exponent. 1.0 follows them exactly, 0.0 ignores both.
@export var walk_speed_follow: float = 1.0
## Random spread on the loop's pitch, rolled once each time a walk starts so
## the loop does not warble as speed changes.
@export_range(0.0, 1.0, 0.01) var walk_pitch_variance: float = 0.04
## Stable detune for THIS player's footsteps, rolled once when the player
## exists. Two players walking at the same speed would otherwise run the
## identical loop at the identical rate, which beats against itself instead
## of reading as two separate sets of feet.
@export_range(0.0, 1.0, 0.01) var walk_instance_detune: float = 0.07
## How far into the clip each walk may start, as a fraction of the clip's
## length: 0.0 always starts at the beginning, 1.0 anywhere in the loop.
## Starting both players' loops at the same point in the file is the other
## half of what makes them phase against each other, so this is what actually
## decorrelates them.
@export_range(0.0, 1.0, 0.01) var walk_start_offset_fraction: float = 1.0
## Clamps, so sliding at dash speed or a slow walk cannot send the footsteps
## to an absurd pitch.
@export var walk_min_pitch: float = 0.6
@export var walk_max_pitch: float = 2.2

@export_group("Jump, landing, dash")
@export var jump_sound: AudioStream = preload("res://assets/soundeffects/JumpSoundEffect.mp3")
@export var jump_volume_db: float = 0.0
@export_range(0.0, 1.0, 0.01) var jump_pitch_variance: float = 0.06
@export var landing_sound: AudioStream = preload("res://assets/soundeffects/LandingSoundEffect.mp3")
@export var landing_volume_db: float = 0.0
@export_range(0.0, 1.0, 0.01) var landing_pitch_variance: float = 0.06
@export var dash_sound: AudioStream = preload("res://assets/soundeffects/DashSoundEffect.mp3")
@export var dash_volume_db: float = 0.0
@export_range(0.0, 1.0, 0.01) var dash_pitch_variance: float = 0.08

@export_group("Attacks")
## Fallback attack sound, used by any move whose MoveData has no
## attack_sound of its own.
@export var default_attack_sound: AudioStream = preload("res://assets/soundeffects/NormalAttackSound.mp3")
## Playback rate for that fallback sound. Below 1.0 drops its pitch, which is
## what this is for; it also slows the clip by the same proportion, which is
## barely audible on a short swing. A move with its own SoundConfig uses that
## config's pitch_scale instead.
@export var attack_pitch_scale: float = 0.9
@export var attack_volume_db: float = -4.0
@export_range(0.0, 1.0, 0.01) var attack_pitch_variance: float = 0.05
## Fallback charge-up, used by special moves with no charge_sound of their
## own. Specials only: a normal goes straight to its attack sound.
@export var default_charge_sound: AudioStream = preload("res://assets/soundeffects/SpecialAttackChargeUP.mp3")
@export var charge_volume_db: float = -3.0
@export_range(0.0, 1.0, 0.01) var charge_pitch_variance: float = 0.03

var _walk_player: AudioStreamPlayer
var _charge_player: AudioStreamPlayer
var _walk_variance: float = 1.0
var _walk_detune: float = 1.0


func _ready() -> void:
	_walk_player = AudioStreamPlayer.new()
	_walk_player.stream = walk_sound
	_walk_player.volume_db = walk_volume_db
	# The clip is authored as a seamless loop but its import sidecar ships
	# with loop off, so looping is enforced here as well as in the .import.
	if _walk_player.stream is AudioStreamMP3:
		_walk_player.stream.loop = true
	add_child(_walk_player)

	# Rolled once for the life of this player, not per walk: a fixed detune
	# between the two fighters' footsteps, so they drift apart rather than
	# sitting on top of each other and beating.
	_walk_detune = SfxManager.random_pitch(1.0, walk_instance_detune)

	_charge_player = AudioStreamPlayer.new()
	add_child(_charge_player)


## Called every frame by Player. move_speed is the player's actual
## horizontal speed, anim_speed_scale the attack speed multiplier that
## already scales every other animation, and is_walking whether the walk
## animation is the one currently showing.
func update_walk(move_speed: float, is_walking: bool, anim_speed_scale: float) -> void:
	if walk_sound == null or not is_walking or move_speed <= 0.0:
		if _walk_player.playing:
			_walk_player.stop()
		return

	if not _walk_player.playing:
		# Rolled once per walk, not per frame, or the loop would warble as
		# the player accelerates. The start offset is re-rolled per walk too,
		# so even this player's own footsteps are not locked to the file's
		# timeline every time.
		_walk_variance = SfxManager.random_pitch(1.0, walk_pitch_variance)
		_walk_player.play(_walk_start_offset())

	var speed_ratio := move_speed / maxf(walk_base_move_speed, 0.001)
	var scaled := pow(maxf(speed_ratio * anim_speed_scale, 0.001), walk_speed_follow)
	_walk_player.pitch_scale = clampf(
		walk_base_pitch * scaled * _walk_variance * _walk_detune,
		walk_min_pitch,
		walk_max_pitch
	)


# Where in the loop this walk starts. Picking a different point per walk is
# what stops two players' identical loops from lining up and phasing; the
# clip is a repeating footstep pattern, so any point in it is a valid start.
func _walk_start_offset() -> float:
	if walk_start_offset_fraction <= 0.0 or _walk_player.stream == null:
		return 0.0
	return randf() * _walk_player.stream.get_length() * walk_start_offset_fraction


func play_jump() -> void:
	SfxManager.play_stream(jump_sound, 1.0, jump_pitch_variance, jump_volume_db)


func play_landing() -> void:
	SfxManager.play_stream(landing_sound, 1.0, landing_pitch_variance, landing_volume_db)


func play_dash() -> void:
	SfxManager.play_stream(dash_sound, 1.0, dash_pitch_variance, dash_volume_db)


## Start of an attack. Specials get their charge-up here, because they are
## slow enough that startup and impact read as two separate moments. Normals
## get nothing: their sound is the impact itself.
func begin_attack(move: MoveData) -> void:
	stop_charge()
	if move == null or move.kind != MoveData.Kind.SPECIAL:
		return

	var config := move.charge_sound
	var stream: AudioStream = config.stream if config else default_charge_sound
	if stream == null:
		return

	_charge_player.stream = stream
	_charge_player.volume_db = SfxManager.master_volume_db + charge_volume_db + (config.volume_db if config else 0.0)
	_charge_player.pitch_scale = SfxManager.random_pitch(config.pitch_scale if config else 1.0, charge_pitch_variance)
	_charge_player.play()


## Active window of an attack: the charge-up hands over to the impact. Uses
## the move's own SoundConfig when it has one, otherwise this player's
## default attack sound.
func play_attack_impact(move: MoveData) -> void:
	stop_charge()

	if move and move.attack_sound and move.attack_sound.stream:
		SfxManager.play(move.attack_sound)
		return
	SfxManager.play_stream(default_attack_sound, attack_pitch_scale, attack_pitch_variance, attack_volume_db)


## Cuts a running charge-up short. Called from Player when an attack ends
## early (interrupted, or the move never reached its active window).
func stop_charge() -> void:
	if _charge_player.playing:
		_charge_player.stop()
