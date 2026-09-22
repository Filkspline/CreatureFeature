extends Node

# ──────────────────────────────────────────────────────────────────
#  SfxManager (Autoload)
#
#  One-shot sound effects. play() takes a SoundConfig, applies its volume
#  and a randomised pitch around its pitch_scale, and plays it on a pooled
#  AudioStreamPlayer, so calls never allocate nodes and overlapping sounds
#  (both fighters landing a hit on the same frame) all get heard.
#
#  Being an autoload, the pooled players outlive scene changes, so a sound
#  fired as a menu option is confirmed is not cut off by the scene it is
#  changing to.
#
#  Deliberately not a catalogue of every sound in the game: each system
#  keeps its own streams in its own exports and only borrows this for the
#  playback mechanics. The one exception is the shared UI set below, which
#  really is the same two sounds on every screen by design.

@export_group("Voices")
## How many sounds may overlap. Once they are all busy, the voice that has
## been playing longest is reused, which is what a burst of hit sounds
## wants.
@export var voice_count: int = 12
## Applied to everything this manager plays, for a global SFX level.
@export var master_volume_db: float = -10.0

@export_group("UI sounds")
## Played whenever the highlighted option in a menu changes. Shared by every
## menu so navigation sounds the same everywhere.
@export var ui_hover_sound: AudioStream = preload("res://assets/soundeffects/UIHoverSoundEffect.mp3")
@export var ui_hover_volume_db: float = 0.0
@export var ui_hover_pitch_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var ui_hover_pitch_variance: float = 0.05
## Played when a menu option is actually confirmed.
@export var ui_select_sound: AudioStream = preload("res://assets/soundeffects/UISelectSoundEffect.mp3")
@export var ui_select_volume_db: float = 0.0
@export var ui_select_pitch_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var ui_select_pitch_variance: float = 0.04

var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0

## Bus and voice used only by play_fitted(), created on first use.
const FITTED_BUS_NAME := "SfxFitted"
## AudioEffectPitchShift's own limits, clamped to rather than trusting a
## caller's maths to stay inside them.
const FITTED_MIN_PITCH := 0.05
const FITTED_MAX_PITCH := 4.0

var _fitted_voice: AudioStreamPlayer
var _fitted_pitch_effect: AudioEffectPitchShift
var _fitted_bus_index: int = -1


func _ready() -> void:
	# PROCESS_MODE_ALWAYS so UI sounds still play while the tree is paused,
	# which is exactly when the pause menu's own navigation sounds happen.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in maxi(voice_count, 1):
		var voice := AudioStreamPlayer.new()
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		_voices.append(voice)


## Plays a config with its own volume, base pitch and pitch variation.
## Returns the voice used, so a caller that needs to cut a sound short (a
## charge-up handing over to its impact) can stop it.
func play(config: SoundConfig) -> AudioStreamPlayer:
	if config == null:
		return null
	return play_stream(config.stream, config.pitch_scale, config.pitch_variance, config.volume_db)


## Plays a raw stream. pitch_variance is a fraction: 0.05 means up to 5%
## either way, re-rolled on every single play.
func play_stream(stream: AudioStream, pitch_scale: float = 1.0, pitch_variance: float = 0.0, volume_db: float = 0.0) -> AudioStreamPlayer:
	if stream == null:
		return null

	var voice := _take_voice()
	voice.stream = stream
	voice.pitch_scale = pitch_scale * _variance_factor(pitch_variance)
	voice.volume_db = master_volume_db + volume_db
	voice.play()
	return voice


func play_ui_hover() -> void:
	play_stream(ui_hover_sound, ui_hover_pitch_scale, ui_hover_pitch_variance, ui_hover_volume_db)


func play_ui_select() -> void:
	play_stream(ui_select_sound, ui_select_pitch_scale, ui_select_pitch_variance, ui_select_volume_db)


## Plays a stream at a chosen speed with its pitch pulled back down
## independently of it. For the rare sound whose LENGTH has to be fitted to
## something on screen (the round countdown's clip is fitted to the visual
## countdown): AudioStreamPlayer.pitch_scale moves speed and pitch together
## by definition, so the speed half goes on the player and the pitch half is
## undone by an AudioEffectPitchShift on a dedicated bus.
##
## speed is the playback rate, correction says how much of the pitch that
## came with it to take back out: 0.0 leaves the pitch coupled, 1.0 brings it
## fully back to the clip's own pitch, and values between are a partial
## correction, which is the knob to tune by ear. Uses its own dedicated
## voice and bus, so a fitted sound can never inherit or leave behind a
## pitch shift on the pooled ones.
func play_fitted(stream: AudioStream, speed: float, correction: float = 1.0, volume_db: float = 0.0) -> AudioStreamPlayer:
	if stream == null:
		return null

	_setup_fitted_bus()
	var safe_speed := maxf(speed, 0.01)
	# pow(1/speed, correction): 1.0 at full correction, 1.0 at none either,
	# which is what makes the knob continuous instead of a switch.
	_fitted_pitch_effect.pitch_scale = clampf(
		pow(1.0 / safe_speed, correction),
		FITTED_MIN_PITCH,
		FITTED_MAX_PITCH
	)
	_fitted_voice.stream = stream
	_fitted_voice.pitch_scale = safe_speed
	_fitted_voice.volume_db = master_volume_db + volume_db
	_fitted_voice.play()
	return _fitted_voice


# One bus with one pitch shifter, created on first use. Done at runtime
# rather than in the project's bus layout so this stays self-contained.
func _setup_fitted_bus() -> void:
	if _fitted_pitch_effect != null:
		return

	_fitted_bus_index = AudioServer.bus_count
	AudioServer.add_bus(_fitted_bus_index)
	AudioServer.set_bus_name(_fitted_bus_index, FITTED_BUS_NAME)
	AudioServer.set_bus_send(_fitted_bus_index, "Master")

	_fitted_pitch_effect = AudioEffectPitchShift.new()
	AudioServer.add_bus_effect(_fitted_bus_index, _fitted_pitch_effect)

	_fitted_voice = AudioStreamPlayer.new()
	_fitted_voice.bus = FITTED_BUS_NAME
	_fitted_voice.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fitted_voice)


## Pitch for one play, with the randomised spread already applied. Public so
## a system that needs to drive its own AudioStreamPlayer - a loop that has
## to be stoppable, say - still varies its pitch the same way everything
## else does instead of rolling its own randomisation.
func random_pitch(pitch_scale: float, pitch_variance: float) -> float:
	return pitch_scale * _variance_factor(pitch_variance)


## The randomised pitch multiplier for one play. Kept here rather than at
## each call site so every repeated sound in the game varies the same way.
func _variance_factor(pitch_variance: float) -> float:
	if pitch_variance <= 0.0:
		return 1.0
	return 1.0 + randf_range(-pitch_variance, pitch_variance)


func _take_voice() -> AudioStreamPlayer:
	if _voices.is_empty():
		# Only reachable if something plays before _ready, which autoload
		# ordering rules out; the lazy voice keeps it from being a crash.
		var voice := AudioStreamPlayer.new()
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		_voices.append(voice)

	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return voice
