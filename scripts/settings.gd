extends Control

# ──────────────────────────────────────────────────────────────────
#  Settings
#
#  The frame around the settings tabs: title, the tabs themselves, and the way
#  out. The values and everything they affect live in GameSettings (autoload),
#  and the rows live in settings_tab_container.
#
#  Deliberately thin: this screen owns no setting, it only routes input. The
#  Exit button is what Navigation lands on first, so the screen is escapable
#  before anything else is touched.
# ──────────────────────────────────────────────────────────────────

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var exit_button : Button = $ExitButton


func _ready():
	exit_button.grab_focus()
	# Navigation on this screen is Godot's own focus handling rather than
	# scripted index changes, so the shared UI sounds are attached to the
	# controls themselves: gaining focus counts as a hover, pressing counts
	# as a select. Deferred so the focus grabbed above does not sound on open.
	call_deferred("_connect_ui_sounds", self)


# Walks the screen and wires up every focusable control and button,
# including whatever the tab container holds.
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


func _process(_delta):
	# Confirm whatever has focus this frame. A focused Button answers ui_accept
	# itself, so this only has to fire when the focused thing does not - which
	# is why the press is emitted rather than the action being re-read.
	if Input.is_action_just_pressed("MenuSelect"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and not (focused as Button).disabled:
			(focused as Button).pressed.emit()

	# B / Circle / Escape leaves, the same as every other menu.
	if Input.is_action_just_pressed("MenuBack"):
		_on_exit_button_pressed()


func _on_exit_button_pressed():
	# Through SceneTransition, like every other screen change in the project, so
	# the fade and the "already changing scene" guard are the same here as they
	# are everywhere else.
	SfxManager.play_ui_select()
	SceneTransition.change_scene(MAIN_MENU_SCENE)
