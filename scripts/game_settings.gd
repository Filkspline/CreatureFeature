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

@export_group("Window sizes")
## Sizes the settings screen offers, smallest first. Every one of them is a
## whole multiple of the 640x360 canvas the game is drawn at: a fractional
## multiple gives some pixels an extra screen pixel and others not, which is
## what makes pixel art shimmer. Keep every entry no taller than the smallest
## display the game will run on - a window bigger than the screen puts its own
## settings row out of reach. Edit this list to offer different sizes.
@export var resolutions : Array[Vector2i] = [
	Vector2i(640, 360),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
]
## Which of them is in use. Saved, so the size only has to be chosen once.
@export var resolution_index : int = 2

## How far inside the screen's usable area the window's top-left corner is kept,
## in pixels. A window is positioned by its CLIENT area, so one sitting at the
## very top of the screen has its title bar drawn above the screen edge: visible,
## but impossible to grab, and so impossible to drag to another monitor. 48px
## clears any standard title bar.
@export var window_margin_px : int = 48

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
	var mode : int = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)

	# Fullscreen ignores the window size, so the size is only asserted while
	# windowed - and again on the way back out of fullscreen, which is exactly
	# when the window has been resized to the display behind our back.
	if not fullscreen:
		apply_resolution()
		_restore_window_decoration()
		_keep_window_on_screen()

	var vsync_mode : int = DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != vsync_mode:
		DisplayServer.window_set_vsync_mode(vsync_mode)


# Puts the window's frame back: the title bar to drag it between monitors by,
# its taskbar entry, and the non-resizable state the project asks for. Coming
# back out of fullscreen - and, on Windows, resizing the window - can leave the
# frame switched off, which is what left a windowed game with nothing to grab.
#
# Deliberately asserted on every windowed display change rather than only when
# leaving fullscreen: a launch that starts without a frame fixes itself, and so
# does one that loses it while playing. Fullscreen is left borderless on
# purpose - a frame around a fullscreen game is exactly what fullscreen is for
# avoiding.
#
# These are flags, so they cannot be read back per launch; they are set FROM the
# project's own display setting, which keeps project.godot the single source of
# truth for how the window behaves instead of hardcoding it twice.
func _restore_window_decoration() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_POPUP, false)
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_RESIZE_DISABLED,
		not bool(ProjectSettings.get_setting("display/window/size/resizable", false))
	)


# Keeps the window somewhere its title bar can actually be reached.
#
# Switching back from fullscreen parks the window at the top-left corner of the
# screen, and because that position is the CLIENT area's, the frame ends up
# above the top edge: the window looks perfectly fine and simply cannot be
# dragged. Enlarging a window that was sitting near an edge runs into the same
# thing from the other side.
#
# Only moved when it needs to be, so a window the player has deliberately put
# somewhere stays exactly where it is.
func _keep_window_on_screen() -> void:
	var screen : int = DisplayServer.window_get_current_screen()
	var usable : Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var size : Vector2i = DisplayServer.window_get_size()
	var position : Vector2i = DisplayServer.window_get_position()
	var margin : int = maxi(window_margin_px, 0)

	# The top-left corner is the part that has to stay reachable, so it wins
	# whenever the window is bigger than the screen and the limits disagree:
	# a title bar you can grab matters more than a strip of window on screen.
	var left_limit : int = usable.position.x + margin
	var top_limit : int = usable.position.y + margin
	var right_limit : int = usable.position.x + usable.size.x - size.x
	var bottom_limit : int = usable.position.y + usable.size.y - size.y

	var target : Vector2i = position
	target.x = maxi(target.x, left_limit)
	target.y = maxi(target.y, top_limit)
	if right_limit >= left_limit:
		target.x = mini(target.x, right_limit)
	if bottom_limit >= top_limit:
		target.y = mini(target.y, bottom_limit)

	if target != position:
		DisplayServer.window_set_position(target)


# ── Window size ──

## The window size currently chosen.
func resolution() -> Vector2i:
	if resolutions.is_empty():
		return DisplayServer.window_get_size()
	return resolutions[clampi(resolution_index, 0, resolutions.size() - 1)]


## What the settings row shows, e.g. "720P  1280X720": the height is the "720p"
## name people ask for, and the pair is the size that actually gets applied.
func resolution_name() -> String:
	var size := resolution()
	return "%dP  %dX%d" % [size.y, size.x, size.y]


## Steps to the next offered size. A single button cycling the list keeps this
## row the same shape as the window mode and V-Sync rows, and stays drivable
## with a d-pad.
func cycle_resolution(direction: int) -> void:
	if resolutions.size() < 2:
		return
	resolution_index = wrapi(resolution_index + direction, 0, resolutions.size())
	_after_change()


# Resizes the window without making it user-resizable: the point of a list of
# sizes is that the game is always at one of them, and dragging a window edge
# would leave it at a size nothing else knows about.
#
# The flag is the inverted one - WINDOW_FLAG_RESIZE_DISABLED, "resizing is off"
# - which is why there is no WINDOW_FLAG_RESIZABLE to reach for. It is already
# on, because the project ships window/size/resizable = false, so it is cleared
# for the resize and turned back on afterwards.
func apply_resolution() -> void:
	var size := resolution()
	if DisplayServer.window_get_size() == size:
		return
	var resize_was_disabled : bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, resize_was_disabled)


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
	config.set_value(SECTION, "resolution_index", resolution_index)
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
	# Clamped rather than trusted: the offered sizes are editable, so a saved
	# index from a longer list must not point off the end of this one.
	resolution_index = clampi(
		int(config.get_value(SECTION, "resolution_index", resolution_index)),
		0,
		maxi(resolutions.size() - 1, 0)
	)
