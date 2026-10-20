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
#  This script owns no button list and no button names. A set is a container
#  (assigned on this node in the Inspector) and its entries are whatever
#  Button nodes are inside it, read in scene order each time the set is shown.
#  Adding, removing, reordering, renaming or hiding a button is therefore an
#  Inspector job, not a code one: the navigation, the pointer and the focus
#  emphasis all follow the tree. A button's art, size, colours and font are its
#  own theme overrides in the scene, and what pressing it does is its own
#  "pressed" connection, also made in the scene.
#
#  Mouse stays visible here (the fight hides it), and selection moves by
#  keyboard/controller or by clicking a button.

@export_group("Sets")
## The two button groups that swap in place. Both are assigned in the scene;
## whichever one is showing is also the one navigation walks.
@export var main_set : VBoxContainer
@export var mode_set : VBoxContainer
## Grows the focused entry so the selection reads at a glance. The same node
## the pause menu uses, assigned in the scene.
@export var focus_emphasis : MenuFocusEmphasis

const PLAYER_SELECT_SCENE := "res://scenes/player_select.tscn"
const SINGLE_PLAYER_SELECT_SCENE := "res://scenes/single_player_select.tscn"
const ONLINE_LOBBY_SCENE := "res://scenes/OnlineLobby.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

# The buttons belonging to whichever set is on screen, in scene order.
var buttons: Array[Button] = []
var selected_index := 0


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Reaching the main menu means no match is in progress, so any session still
	# open - a fight that finished, a paused match quit out of, a lobby left
	# behind - is closed here. Otherwise the next Local Multiplayer select would
	# still believe it is an online match and sit waiting for a peer that is gone.
	if MultiplayerManager.is_online():
		MultiplayerManager.leave_game()
	GameManager.clear_online_state()
	_show_main_set()
	_bob_logo()


# The logo breathes, the same way an idle card does: a small vertical bob that
# never settles, so the menu is never completely still.
func _bob_logo() -> void:
	# Cast rather than left as Node: get_node_or_null() returns a Node, whose
	# .position has no type for the analyser to infer from.
	var logo := get_node_or_null("Logo") as Node2D
	if logo == null:
		return
	var base_y : float = logo.position.y
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(logo, "position:y", base_y - 3.0, 1.6)
	tween.tween_property(logo, "position:y", base_y, 1.6)


# Swaps the visible set and hands navigation the entries found inside it. Called
# with the set that should be shown; the other one is hidden outright.
func _show_set(set_root: VBoxContainer) -> void:
	if set_root == null:
		push_warning("MainMenu: a button set is not assigned in the scene, nothing to show")
		return

	main_set.visible = set_root == main_set
	mode_set.visible = set_root == mode_set

	buttons = _collect_buttons(set_root)
	selected_index = 0

	if buttons.is_empty():
		return
	buttons[0].grab_focus()
	if focus_emphasis:
		focus_emphasis.register_buttons(buttons)


# Every Button inside a set, in the order the scene lists them. Recursive so a
# set that groups its buttons (an HBox of two, say) still works, and skipping
# hidden ones so unticking "Visible" on a button in the Inspector is all it
# takes to drop it out of the menu.
func _collect_buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	for child in node.get_children():
		var button := child as Button
		if button:
			if button.visible:
				found.append(button)
			continue
		found.append_array(_collect_buttons(child))
	return found


func _show_main_set() -> void:
	_show_set(main_set)


func _show_mode_set() -> void:
	_show_set(mode_set)


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

# Practice Range is the single-player mode, so it has its own input select
# screen (single_player_select.tscn) rather than a single-player mode switch
# inside local multiplayer's. That screen lays the one creature's slot and the
# tray of waiting input cursors out in different parts of the screen, so a
# device that has just pressed a button is never drawn on top of the slot it has
# not claimed yet. mode_id 2 is what both that screen and the lab read to know
# they are in the single-player flow.
func _on_practice_range_pressed() -> void:
	SfxManager.play_ui_select()
	GameManager.mode_id = 2
	SceneTransition.change_scene(SINGLE_PLAYER_SELECT_SCENE)


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
