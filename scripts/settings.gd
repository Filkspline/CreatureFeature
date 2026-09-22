extends Control

@onready var exit_button = $ExitButton


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
	# Custom select button
	if Input.is_action_just_pressed("MenuSelect"):
		var focused = get_viewport().gui_get_focus_owner()
		
		if focused != null:
			print("Focused: ", focused)
			
			# Normal buttons
			if focused is Button:
				focused.pressed.emit()


	# B / Circle
	if Input.is_action_just_pressed("MenuBack"):
		_on_exit_button_pressed()


func _on_exit_button_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
