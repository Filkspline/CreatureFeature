extends Control

# ──────────────────────────────────────────────────────────────────
#  SettingsTabContainer
#
#  The three tabs of the settings screen, and nothing else: every value lives
#  in GameSettings, which applies it and saves it. This is only the front end.
#
#  Volume rows are a value plus two buttons rather than sliders, deliberately.
#  The whole game is menu-driven and mostly played on a pad, and a slider is the
#  one control a d-pad cannot drive; two focusable buttons need nothing that the
#  rest of the menus do not already use.
# ──────────────────────────────────────────────────────────────────

## The movement keys, in the order they are listed on the Controls tab.
const MOVE_BASES := ["Left", "Right", "Up", "Down"]
const ACTION_BASES := ["Normal", "Special", "Jump"]

@onready var tab_container : TabContainer = $TabContainer
@onready var window_mode_button : Button = $TabContainer/General/WindowModeRow/WindowModeButton
@onready var vsync_button : Button = $TabContainer/General/VsyncRow/VsyncButton
@onready var sfx_value : Label = $TabContainer/Sound/SfxRow/SfxValue
@onready var music_value : Label = $TabContainer/Sound/MusicRow/MusicValue
@onready var ui_value : Label = $TabContainer/Sound/UiRow/UiValue
@onready var p1_keys : Label = $TabContainer/Controls/P1Keys
@onready var p2_keys : Label = $TabContainer/Controls/P2Keys


func _ready():
	# Tabs are switched with MenuTabLeft/MenuTabRight, not by focusing the tab
	# bar: on a pad that would put a second, invisible focus layer in front of
	# the rows the player is actually trying to reach.
	var tab_bar := tab_container.get_tab_bar()
	tab_bar.focus_mode = Control.FOCUS_NONE
	GameSettings.changed.connect(_refresh)
	_refresh()


func _process(_delta):
	if Input.is_action_just_pressed("MenuTabLeft"):
		tab_container.current_tab -= 1
		if tab_container.current_tab < 0:
			tab_container.current_tab = tab_container.get_tab_count() - 1
		SfxManager.play_ui_hover()

	if Input.is_action_just_pressed("MenuTabRight"):
		tab_container.current_tab += 1
		if tab_container.current_tab >= tab_container.get_tab_count():
			tab_container.current_tab = 0
		SfxManager.play_ui_hover()


# ── Rows ──

func _on_window_mode_pressed() -> void:
	GameSettings.toggle_fullscreen()


func _on_vsync_pressed() -> void:
	GameSettings.toggle_vsync()


func _on_sfx_minus_pressed() -> void:
	GameSettings.set_sfx_volume(GameSettings.step_volume(GameSettings.sfx_volume, -1))


func _on_sfx_plus_pressed() -> void:
	GameSettings.set_sfx_volume(GameSettings.step_volume(GameSettings.sfx_volume, 1))


func _on_music_minus_pressed() -> void:
	GameSettings.set_music_volume(GameSettings.step_volume(GameSettings.music_volume, -1))


func _on_music_plus_pressed() -> void:
	GameSettings.set_music_volume(GameSettings.step_volume(GameSettings.music_volume, 1))


func _on_ui_minus_pressed() -> void:
	GameSettings.set_ui_volume(GameSettings.step_volume(GameSettings.ui_volume, -1))


func _on_ui_plus_pressed() -> void:
	# The select sound is played by the button itself through the shared UI
	# wiring, so a step up is heard at the new level straight away.
	GameSettings.set_ui_volume(GameSettings.step_volume(GameSettings.ui_volume, 1))


# ── Showing the current settings ──

func _refresh() -> void:
	window_mode_button.text = "FULLSCREEN" if GameSettings.fullscreen else "WINDOWED"
	vsync_button.text = "ON" if GameSettings.vsync else "OFF"
	sfx_value.text = _percent(GameSettings.sfx_volume)
	music_value.text = _percent(GameSettings.music_volume)
	ui_value.text = _percent(GameSettings.ui_volume)
	p1_keys.text = _controls_text("P1")
	p2_keys.text = _controls_text("P2")


func _percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


# The keys are read from the same captured table the select screens and the
# fight itself bind from (GameManager.keyboard_layouts), so this tab can never
# claim a key the game does not actually use.
func _controls_text(suffix: String) -> String:
	var layout : Dictionary = GameManager.keyboard_layouts.get(suffix, {})
	if layout.is_empty():
		return "NO KEYBOARD BINDINGS CAPTURED."

	var move := ""
	for base in MOVE_BASES:
		move += _key_name(layout, base) + "  "
	var actions := ""
	for base in ACTION_BASES:
		actions += "%s  %s     " % [base.to_upper(), _key_name(layout, base)]

	return "MOVE   %s\n%s" % [move.strip_edges(), actions.strip_edges()]


func _key_name(layout: Dictionary, base: String) -> String:
	var events : Array = layout.get(base, [])
	for event in events:
		if not (event is InputEventKey):
			continue
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode
		if code == KEY_NONE:
			code = key_event.keycode
		if code == KEY_NONE:
			continue
		return _readable_key(code)
	return "-"


# OS.get_keycode_string gives the name printed on the key ("W", "Left",
# "Numpad 4"), which is what a player needs to read here.
func _readable_key(code: int) -> String:
	var text := OS.get_keycode_string(code)
	return text.to_upper() if text.length() <= 2 else text
