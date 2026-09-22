extends CanvasLayer

# ──────────────────────────────────────────────────────────────────
#  RoundCountdown
#
#  The "3, 2, 1" that plays every time the fight level loads: round 1 of a
#  match and every round after an upgrade draft, since both are a fresh
#  load of test_level.tscn. TEST_level_script spawns one per round.
#
#  While it plays, players can't act, but nothing else changes: no pause,
#  no time_scale, physics/animation/timers/hit reactions all keep running.
#  That lock is GameManager.player_input_locked and this node owns it for
#  exactly as long as it is alive, so finishing normally, being freed, or
#  the whole level being swapped out all hand control back.
#
#  Each number is stamped in with the project's usual squash and stretch:
#  wide and flat, stretching thin and tall as it pops, overshooting,
#  settling, holding, then squashing away as the next one comes in.

@export_group("Timing")
## How long each number sits at full size before the next one pops in.
@export var number_hold_duration : float = 0.35
## How long a number takes to pop from its squashed first frame out to its
## stretched peak. Short and snappy is what makes it feel like an impact.
@export var pop_duration : float = 0.09
## How long a number takes to come back down from the stretched peak,
## through the overshoot, to its resting size.
@export var settle_duration : float = 0.10
## How long a number takes to squash away as the next one pops in.
@export var exit_duration : float = 0.08

@export_group("Squash & stretch")
## Shape each number starts in, about to be stamped flat.
@export var squash_scale : Vector2 = Vector2(2.2, 0.3)
## The thin, tall peak the pop carries it to before it settles back.
@export var stretch_scale : Vector2 = Vector2(0.6, 1.5)
## What it stretches through on the way back down, before landing on its
## resting size. Bigger values read as a harder stop.
@export var overshoot_scale : Vector2 = Vector2(1.18, 1.18)
## Flat and wide again as it leaves, mirrored from the entry pose.
@export var exit_squash_scale : Vector2 = Vector2(1.9, 0.35)
## Random tilt, in degrees, that each number pops in with, levelling out as
## it settles. 0.0 for a dead straight countdown.
@export var pop_tilt_degrees : float = 7.0

@export_group("Scene transition")
## Longest the countdown will wait for the transition's mouth to finish
## opening before starting anyway. This is only a safety cap: without it, a
## transition that never reported itself finished would hold both players
## locked out forever.
@export var transition_wait_max : float = 1.0

@export_group("Sound")
## Countdown clip, played once when the numbers start.
@export var countdown_sound : AudioStream = preload("res://assets/soundeffects/Countdown321.mp3")
@export var countdown_volume_db : float = 0.0
## Nudge on top of the fitted playback speed below, to taste, without having
## to recalculate anything by hand.
@export var countdown_sound_speed : float = 1.0
## How much of the pitch that the fitted speed brought with it to take back
## out. Fitting the clip to the countdown's length means playing it faster,
## and pitch_scale moves speed and pitch together, so speeding it up also
## raised it. 1.0 restores the clip's own pitch at the fitted speed, 0.0
## leaves it coupled (whatever the speed did to it), and values between are
## a half correction, which is the knob to tune by ear.
@export_range(0.0, 2.0, 0.01) var countdown_pitch_correction : float = 1.0

@onready var number_sprite : Sprite2D = $Number

## The scale the sprite is authored with in the scene. Every squash and
## stretch value above is applied as a multiplier on top of this, so
## resizing the countdown is a matter of changing the sprite's own scale.
var _base_scale : Vector2


func _ready() -> void:
	_base_scale = number_sprite.scale
	number_sprite.visible = false
	GameManager.set_player_input_locked(true)
	_run_countdown()


# Pops every frame of the sheet in order, then hands control back.
# hframes is the number of frames in the sheet, so a sheet with two or four
# numbers in it needs no change here (three frames today: 3, 2, 1).
func _run_countdown() -> void:
	await _wait_for_scene_transition()
	_play_countdown_sound()
	number_sprite.visible = true
	for frame_index in number_sprite.hframes:
		number_sprite.frame = frame_index
		await _play_number()
	_finish()


# Real seconds the whole countdown takes, derived from the same exports that
# drive the numbers: each one pops, settles, holds, then squashes away.
func countdown_duration() -> float:
	return float(number_sprite.hframes) * (
		pop_duration + settle_duration + number_hold_duration + exit_duration
	)


# Playback rate that makes the clip finish exactly when the last number
# does. Derived rather than hand-set, so retiming the countdown above keeps
# the sound lined up on its own: countdown_sound_speed only nudges that fit.
func countdown_sound_pitch() -> float:
	if countdown_sound == null:
		return 1.0
	var clip_length := countdown_sound.get_length()
	var total := countdown_duration()
	if clip_length <= 0.0 or total <= 0.0:
		return countdown_sound_speed
	return (clip_length / total) * countdown_sound_speed


func _play_countdown_sound() -> void:
	if countdown_sound == null:
		return
	# Printed once per round so the fit is visible when retiming the numbers
	# rather than something you have to work out with a stopwatch.
	print("[COUNTDOWN] sound fitted to a %.2fs countdown at %.2fx speed (clip is %.2fs), pitch correction %.2f"
		% [countdown_duration(), countdown_sound_pitch(), countdown_sound.get_length(), countdown_pitch_correction])
	# Fitted rather than plain-played, because the playback rate that lines
	# the clip up with the numbers also raises its pitch; the correction
	# takes that pitch back out without touching the timing.
	SfxManager.play_fitted(
		countdown_sound,
		countdown_sound_pitch(),
		countdown_pitch_correction,
		countdown_volume_db
	)


# SceneTransition swaps the scene part way through its mouth animation (at
# 0.2667s of 0.6s), so the mouth is still opening when this node appears.
# Waiting it out is what keeps the first number from popping behind the
# wipe. Bounded, so a transition that never reports itself finished can only
# ever delay the countdown rather than hold the players locked out for good.
func _wait_for_scene_transition() -> void:
	var waited := 0.0
	while SceneTransition.is_transitioning and waited < transition_wait_max:
		waited += get_process_delta_time()
		await get_tree().process_frame


# One number: stamp in, settle back, hold, squash away. Awaited by the loop
# above so each number finishes completely before the next one appears.
func _play_number() -> void:
	number_sprite.scale = _base_scale * squash_scale
	number_sprite.modulate.a = 0.0
	number_sprite.rotation = deg_to_rad(randf_range(-pop_tilt_degrees, pop_tilt_degrees))

	var tween := create_tween()
	# Pop: the flat, wide pose snaps out to thin and tall, fading in as it
	# goes, with the tilt springing past level thanks to TRANS_BACK.
	tween.tween_property(number_sprite, "modulate:a", 1.0, pop_duration)
	tween.parallel().tween_property(number_sprite, "scale", _base_scale * stretch_scale, pop_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(number_sprite, "rotation", 0.0, pop_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Settle: overshoot past the resting size, then come back onto it.
	tween.tween_property(number_sprite, "scale", _base_scale * overshoot_scale, settle_duration * 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(number_sprite, "scale", _base_scale, settle_duration * 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Hold, then squash away into the next number.
	tween.tween_interval(number_hold_duration)
	tween.tween_property(number_sprite, "scale", _base_scale * exit_squash_scale, exit_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(number_sprite, "modulate:a", 0.0, exit_duration)

	await tween.finished


# Normal ending: the last number has squashed away, so the countdown hides
# and play begins.
func _finish() -> void:
	number_sprite.visible = false
	GameManager.set_player_input_locked(false)


# Safety net. If this node goes away without reaching _finish() (the level
# being swapped out mid-countdown, an editor hot-reload, anything that frees
# it early), players must not be left locked out, so control is handed back
# here too. Guarded because autoloads can already be gone during shutdown.
func _exit_tree() -> void:
	if GameManager:
		GameManager.set_player_input_locked(false)
