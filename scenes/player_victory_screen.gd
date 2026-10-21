extends Node2D

# ──────────────────────────────────────────────────────────────────
#  player_victory - the match-end screen
#
#  Runs in two beats: the winner's art slams in on its own, then after a short
#  beat the two options pop up. That ordering is the whole point - the result
#  should land before the player is asked what to do about it.
#
#  Both options are real Buttons (the shared menu_button scene), so pad and
#  keyboard work through ordinary focus navigation and the mouse works on top of
#  that. Nothing here reads a hardcoded device: whatever the player used on the
#  select screen has already been bound by GameManager.bind_player_inputs().
# ──────────────────────────────────────────────────────────────────

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const PRE_FIGHT_SCENE := "res://scenes/pre_fight_upgrade_screen.tscn"

## How long the winner art holds on the screen alone before the options appear.
@export var options_delay : float = 1.6
## How long the art takes to slam in.
@export var pop_duration : float = 0.45
## How far oversized the art starts before it settles.
@export var pop_from_scale : float = 1.35

@onready var p1_win : Node2D = $p1_win
@onready var p2_win : Node2D = $p2_win
@onready var play_again_button : Button = $PlayAgainButton
@onready var menu_button : Button = $MenuButton


func _ready() -> void:
	p1_win.hide()
	p2_win.hide()
	play_again_button.hide()
	menu_button.hide()

	_show_winner()
	_bob_win_text()

	# The round-end sting, slowed right down: this is the MATCH ending, not a
	# round, so it should land heavier and longer than the one inside the fight.
	SfxManager.play_stream(
		GameManager.round_end_sound, 0.6, 0.0, GameManager.round_end_volume_db
	)

	await get_tree().create_timer(options_delay).timeout
	if not is_inside_tree():
		return
	_show_options()
	call_deferred("_connect_ui_sounds", self)


func _show_winner() -> void:
	if GameManager.win_id == 1:
		p1_win.show()
	else:
		p2_win.show()

	# Each sprite slams in from oversized with a fade, so the result has some
	# weight to it instead of just being there when the scene loads.
	for sprite in get_tree().get_nodes_in_group("win_text") as Array[Node]:
		if not (sprite is Sprite2D) or not sprite.is_visible_in_tree():
			continue
		var art := sprite as Sprite2D
		var base_scale := art.scale
		art.scale = base_scale * pop_from_scale
		art.modulate.a = 0.0
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(art, "scale", base_scale, pop_duration)
		tween.parallel().tween_property(art, "modulate:a", 1.0, pop_duration * 0.5)
	_show_background_pop()


# The backgrounds are the other children of the winning group, so they get the
# same treatment a beat behind the text.
func _show_background_pop() -> void:
	var winner := p1_win if GameManager.win_id == 1 else p2_win
	for child in winner.get_children():
		if not (child is Sprite2D) or child.is_in_group("win_text"):
			continue
		var art := child as Sprite2D
		var base_scale := art.scale
		art.scale = base_scale * pop_from_scale
		art.modulate.a = 0.0
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(art, "scale", base_scale, pop_duration * 1.2)
		tween.parallel().tween_property(art, "modulate:a", 1.0, pop_duration * 0.6)


func _bob_win_text() -> void:
	var text_array := get_tree().get_nodes_in_group("win_text") as Array[Node]
	if text_array == null:
		return
	for text in text_array:
		var base_y : float = text.position.y
		var tween := create_tween().set_loops()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(text, "position:y", base_y - 3.0, 1.6)
		tween.tween_property(text, "position:y", base_y, 1.6)


# Second beat: the options, popped in one after the other so the eye follows
# them in, with the first one focused so pad and keyboard can act immediately.
func _show_options() -> void:
	play_again_button.show()
	menu_button.show()
	if play_again_button.has_method("pop_in"):
		play_again_button.call("pop_in")
	if menu_button.has_method("pop_in"):
		menu_button.call("pop_in")
	play_again_button.grab_focus()


func _process(_delta: float) -> void:
	if not play_again_button.visible:
		return

	# Moving between the two options is done by hand, the same way the main menu
	# does it. These buttons hang off a Node2D rather than a Control, so the
	# engine has no Control parent to work focus neighbours out from and its own
	# ui_left / ui_right navigation does nothing here - which is why only the
	# button that started focused could ever be pressed.
	var focused := get_viewport().gui_get_focus_owner()
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("MenuUp"):
		_select_button(0)
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("MenuDown"):
		_select_button(1)

	# Same convention as every other menu: MenuSelect confirms whatever has
	# focus, MenuBack takes the "back" option.
	if Input.is_action_just_pressed("MenuSelect"):
		if focused is Button and not (focused as Button).disabled:
			(focused as Button).pressed.emit()
	if Input.is_action_just_pressed("MenuBack"):
		_on_menu_button_pressed()


# Moves focus onto one of the two options. Focus is what decides everything here:
# the selector follows it (see menu_button.selector_follows_focus) and
# MenuSelect presses whichever button holds it.
func _select_button(index: int) -> void:
	var buttons: Array[Button] = [play_again_button, menu_button]
	var target := buttons[clampi(index, 0, buttons.size() - 1)]
	if target == get_viewport().gui_get_focus_owner():
		return
	target.grab_focus()
	SfxManager.play_ui_hover()


# Walks the screen and wires the shared UI sounds onto every button, the same
# way the settings and lobby screens do, so this end screen is not the one
# silent place left in the game.
func _connect_ui_sounds(node: Node) -> void:
	var button := node as Button
	if button and not button.pressed.is_connected(SfxManager.play_ui_select):
		button.pressed.connect(SfxManager.play_ui_select)
	var control := node as Control
	if control and control.focus_mode != Control.FOCUS_NONE:
		if not control.focus_entered.is_connected(SfxManager.play_ui_hover):
			control.focus_entered.connect(SfxManager.play_ui_hover)
	for child in node.get_children():
		_connect_ui_sounds(child)


func _on_play_again_pressed() -> void:
	# Straight back to the upgrade draft, with the match reset first: the same
	# clean pre-match state a fresh match starts from, so round counts and picked
	# upgrades do not carry over.
	SfxManager.play_ui_select()
	_reset_match()
	SceneTransition.change_scene(PRE_FIGHT_SCENE)


func _on_menu_button_pressed() -> void:
	SfxManager.play_ui_select()
	_reset_match()
	SceneTransition.change_scene(MAIN_MENU_SCENE)


func _reset_match() -> void:
	GameManager.reset_player_select()
	GameManager.start_match()
	GameManager.win_id = 0
