extends Node2D

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

@export var hand_limit : int = 5 # Default 5
@export var hand_width : float = 200 # Measured in pixels 200 is good for 5 cards
@export var spread_curve: Curve
@export var height_curve: Curve
@export var rotation_curve: Curve

var card_default_z_index : int = hand_limit
var hand = self
var current_z_index : int
var card_default_transform : Transform2D
var card_default_rotation : float
var defaults_set : bool
var selected_card_idx : int

##------------------------------------------------------------------------

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_draw_hand()

func _draw_hand() -> void:
	current_z_index = card_default_z_index
	for _x in hand_limit:
		var upgarde_card = UPGRADE_CARD.instantiate()
		if defaults_set != true:
			card_default_transform = upgarde_card.transform
			card_default_rotation = upgarde_card.rotation
			defaults_set = true
		
		add_child(upgarde_card)
		upgarde_card.z_index = current_z_index
		current_z_index -= 1
	
	await get_tree().create_timer(0.5).timeout
	_spread_cards()


func _spread_cards() -> void:
	for card in hand.get_children():
		var hand_ratio = float(card.get_index())/float(self.get_child_count()-1)
		var destination = hand.global_transform
		
		# Calculates the locations of the card in the hand
		destination.origin.x += spread_curve.sample(hand_ratio) * hand_width
		destination.origin += height_curve.sample(hand_ratio) * (Vector2.UP * 15)
		
		# Sets the card locations the the assigned destinations
		var tween = create_tween()
		tween.tween_property(card, "transform", destination, 0.4)
		tween.parallel().tween_property(card, "rotation", rotation_curve.sample(hand_ratio) * -0.3, 0.4)
		await get_tree().create_timer(0.5).timeout
	
	hand.get_child(0).currently_highlighted = true
	hand.get_child(0)._handle_highlight()
	selected_card_idx = 0
	
func _input(event: InputEvent) -> void:
	# Handles the input for the ui menu, god help us all
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	elif event is InputEventKey:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if event.keycode == KEY_A and event.pressed:
			if selected_card_idx == 0:
				pass
			else:
				selected_card_idx -= 1
				hand.get_child(selected_card_idx).currently_highlighted = true
				hand.get_child(selected_card_idx)._handle_highlight()
		elif event.keycode == KEY_D and event.pressed:
			if selected_card_idx == (hand_limit - 1):
				pass
			else:
				selected_card_idx += 1
				hand.get_child(selected_card_idx).currently_highlighted = true
				hand.get_child(selected_card_idx)._handle_highlight()

	elif event is InputEventJoypadButton:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if event.button_index == JOY_BUTTON_DPAD_LEFT and event.pressed:
			if selected_card_idx == 0:
				pass
			else:
				selected_card_idx -= 1
				hand.get_child(selected_card_idx).currently_highlighted = true
				hand.get_child(selected_card_idx)._handle_highlight()
		elif event.button_index == JOY_BUTTON_DPAD_RIGHT and event.pressed:
			if selected_card_idx == (hand_limit - 1):
				pass
			else:
				selected_card_idx += 1
				hand.get_child(selected_card_idx).currently_highlighted = true
				hand.get_child(selected_card_idx)._handle_highlight()

	elif event is InputEventJoypadMotion:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		pass 

	if event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_A:
			_handle_clicked_card()
	elif event is InputEventKey:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_handle_clicked_card()


func _handle_clicked_card():
	var highlighted_card : Node2D
	for card in hand.get_children():
		if card.currently_highlighted == false:
			hand.remove_child(card)
			card.queue_free()
		else:
			highlighted_card = card
	# Handles moving the selected card to the center of the screen,
	# can be changed to move to a specific node down the line
	var tween = create_tween()
	tween.tween_property(highlighted_card, "transform", card_default_transform, 0.4)
	tween.parallel().tween_property(highlighted_card, "rotation", card_default_rotation, 0.4)
	# TODO to handle vfx if wanted or any other processes do so after the above code
