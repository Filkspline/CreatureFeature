extends Node

# ──────────────────────────────────────────────────────────────────
#  GameSettings (autoload)
#
#  The one place the player's choices about how the game plays live.
#
#  It has to be an autoload for two reasons: the values must survive the scene
#  changes every menu makes (SceneTransition reloads the whole tree), and some
#  of them can only be applied once the thing they affect exists.
#
#  Volume is stored as a MULTIPLIER, not as a level. Every sound in the project
#  is already tuned by hand - SfxManager's own master_volume_db defaults to -10,
#  each sound carries its own offset - so a slider that wrote an absolute dB
#  value would throw that tuning away the moment it was touched. Instead the
#  level each system starts with is remembered as its reference and the slider
#  scales it: 100% is exactly the tuned default, 0% is silence.
# ──────────────────────────────────────────────────────────────────

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "settings"

## How far one press of a volume row's -/+ moves the value.
const VOLUME_STEP := 0.1

## Where a fully turned-down volume lands. linear_to_db(0.0) is -inf, which
## mutes the sound outright rather than fading it, so a floor is used instead.
const MIN_VOLUME_DB := -60.0

## Emitted after anything changes, so an open settings screen can refresh.
signal changed

var sfx_volume : float = 1.0
var music_volume : float = 1.0
var ui_volume : float = 1.0
var fullscreen : bool = false
var vsync : bool = true

# The levels the game was tuned to, captured before anything is applied, so
# "100%" means the sound the project shipped with rather than some new one.
var _sfx_reference_db : float = -10.0
var _ui_hover_reference_db : float = 0.0
var _ui_select_reference_db : float = 0.0


func _ready() -> void:
	_capture_reference_levels()
	load_settings()
	apply_all()


# ── Applying ──

func apply_all() -> void:
	apply_volumes()
	apply_display()
	changed.emit()


func apply_volumes() -> void:
	if SfxManager != null:
		SfxManager.master_volume_db = _scaled_db(_sfx_reference_db, sfx_volume)
		SfxManager.ui_hover_volume_db = _scaled_db(_ui_hover_reference_db, ui_volume)
		SfxManager.ui_select_volume_db = _scaled_db(_ui_select_reference_db, ui_volume)
	if GameManager != null:
		GameManager.set_music_volume(_scaled_db(0.0, music_volume))


func apply_display() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)

	var vsync_mode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != vsync_mode:
		DisplayServer.window_set_vsync_mode(vsync_mode)


func _capture_reference_levels() -> void:
	if SfxManager == null:
		return
	_sfx_reference_db = SfxManager.master_volume_db
	_ui_hover_reference_db = SfxManager.ui_hover_volume_db
	_ui_select_reference_db = SfxManager.ui_select_volume_db


func _scaled_db(reference_db: float, scale: float) -> float:
	if scale <= 0.001:
		return MIN_VOLUME_DB
	return maxf(reference_db + linear_to_db(scale), MIN_VOLUME_DB)


# ── What the settings screen calls ──

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_after_change()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_after_change()


func set_ui_volume(value: float) -> void:
	ui_volume = clampf(value, 0.0, 1.0)
	_after_change()


## Moves a 0..1 volume by one step in the given direction and returns it, so a
## row can be written as "value = step(value, 1)". Stepping in fixed amounts is
## what makes a volume row work on a pad: a slider needs a pointer, two buttons
## need nothing but the d-pad every other menu already uses.
func step_volume(value: float, direction: int) -> float:
	var stepped := snappedf(value + float(direction) * VOLUME_STEP, 0.001)
	return clampf(stepped, 0.0, 1.0)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	_after_change()


func toggle_vsync() -> void:
	vsync = not vsync
	_after_change()


func _after_change() -> void:
	apply_all()
	save_settings()


# ── Saving ──
# There was no persistence anywhere in the project before this: every value in
# the game lived for one run. These are scalars, so a ConfigFile in user:// is
# enough, and it is the only file the game writes.

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "sfx_volume", sfx_volume)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "ui_volume", ui_volume)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "vsync", vsync)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("GameSettings: could not save %s (%s)" % [CONFIG_PATH, error_string(error)])


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return # no file yet: the defaults above are the settings
	sfx_volume = clampf(config.get_value(SECTION, "sfx_volume", sfx_volume), 0.0, 1.0)
	music_volume = clampf(config.get_value(SECTION, "music_volume", music_volume), 0.0, 1.0)
	ui_volume = clampf(config.get_value(SECTION, "ui_volume", ui_volume), 0.0, 1.0)
	fullscreen = bool(config.get_value(SECTION, "fullscreen", fullscreen))
	vsync = bool(config.get_value(SECTION, "vsync", vsync))
