extends Node2D

# ──────────────────────────────────────────────────────────────────
#  MainMenu
#
#  Two sets of buttons that swap in place: the top-level set (Play /
#  Settings / Quit) and the mode set that Play opens (Practice Range /
#  Online Multiplayer / Local Multiplayer / Back). Only one set is ever
#  visible, both sit in the same spot, so pressing Play reads as the buttons
#  themselves changing rather than a new screen opening.
#
#  Navigation, the SelectionPointer and MenuFocusEmphasis all work off the
#  button list of whichever set is up, so each set is navigable on its own
#  and neither can scroll into the other's entries.
#
#  Mouse stays visible here (the fight hides it), and selection moves by
#  keyboard/controller or by clicking a button.

@onready var main_set : VBoxContainer = $Buttons/MainMenuButtons
@onready var mode_set : VBoxContainer = $Buttons/ModeButtons

@onready var play_button : Button = $Buttons/MainMenuButtons/Play
@onready var settings_button : Button = $Buttons/MainMenuButtons/Settings
@onready var quit_button : Button = $Buttons/MainMenuButtons/Quit

@onready var practice_button : Button = $Buttons/ModeButtons/PracticeRange
@onready var online_button : Button = $Buttons/ModeButtons/Online
@onready var local_button : Button = $Buttons/ModeButtons/Local
@onready var back_button : Button = $Buttons/ModeButtons/Back

# Grows the focused entry so the selection reads at a glance. A real node in
# the scene, so its scale and timing are tuned in the Inspector.
@onready var focus_emphasis : MenuFocusEmphasis = get_node_or_null("MenuFocusEmphasis")

const PLAYER_SELECT_SCENE := "res://scenes/player_select.tscn"
const ONLINE_LOBBY_SCENE := "res://scenes/OnlineLobby.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

# The buttons belonging to whichever set is on screen. Everything below reads
# this instead of a fixed list, so the two sets can't bleed into each other.
var buttons: Array[Button] = []
var selected_index := 0


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main_set()


# Swaps the visible set and hands navigation the matching button list. Called
# with the set that should be shown; the other one is hidden outright.
func _show_set(set_root: VBoxContainer, set_buttons: Array[Button]) -> void:
	main_set.visible = set_root == main_set
	mode_set.visible = set_root == mode_set

	buttons = set_buttons
	selected_index = 0

	if buttons.is_empty():
		return
	buttons[0].grab_focus()
	if focus_emphasis:
		focus_emphasis.register_buttons(buttons)


func _show_main_set() -> void:
	_show_set(main_set, [play_button, settings_button, quit_button])


func _show_mode_set() -> void:
	_show_set(mode_set, [practice_button, online_button, local_button, back_button])


func _process(_delta):
	if buttons.is_empty():
		return

	# Move selection down
	if Input.is_action_just_pressed("MenuDown"):
		selected_index += 1
		if selected_index >= buttons.size():
			selected_index = 0

		buttons[selected_index].grab_focus()
		SfxManager.play_ui_hover()

	# Move selection up
	if Input.is_action_just_pressed("MenuUp"):
		selected_index -= 1
		if selected_index < 0:
			selected_index = buttons.size() - 1

		buttons[selected_index].grab_focus()
		SfxManager.play_ui_hover()

	# Select current button
	if Input.is_action_just_pressed("MenuSelect"):
		buttons[selected_index].pressed.emit()


# ── Top-level set ──

func _on_play_pressed() -> void:
	SfxManager.play_ui_select()
	_show_mode_set()


func _on_settings_pressed():
	SfxManager.play_ui_select()
	SceneTransition.change_scene(SETTINGS_SCENE)


func _on_quit_pressed():
	SfxManager.play_ui_select()
	get_tree().quit()


# ── Mode set ──

# Practice Range is the single-player mode, and it goes through the SAME input
# select screen local multiplayer uses, in its single-player mode (mode_id 2).
# That is the point: the cut-down one-slot screen it used to have claimed the
# first device that pressed anything and then ignored every other one, so a
# player who brushed the keyboard was stuck with it for the whole session. Here
# every device that presses a button gets its own cursor, the player takes the
# creature's slot with Normal, can release it with Special, and starts once it
# is held - identical to local multiplayer, with the second creature being the
# training dummy rather than a second player.
func _on_practice_range_pressed() -> void:
	SfxManager.play_ui_select()
	GameManager.mode_id = 2
	SceneTransition.change_scene(PLAYER_SELECT_SCENE)


# Online goes to the lobby first: the lobby owns the session handshake and
# hands off to player select once a peer is actually connected. mode_id is
# pinned to 1 (the fighting flow) so a previous Practice Range session can't
# leave mode_id on 2 and send a connected online session to the lab.
func _on_online_pressed() -> void:
	SfxManager.play_ui_select()
	GameManager.mode_id = 1
	SceneTransition.change_scene(ONLINE_LOBBY_SCENE)


func _on_local_multiplayer_pressed() -> void:
	SfxManager.play_ui_select()
	GameManager.mode_id = 1
	SceneTransition.change_scene(PLAYER_SELECT_SCENE)


func _on_back_pressed() -> void:
	SfxManager.play_ui_select()
	_show_main_set()
