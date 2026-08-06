extends Node2D

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

@export var hand_limit : int = 5 # Default 5
@export var hand_width : float = 500 # Measured in pixels 200 is good for 5 cards
@export var min_card_spacing : float = 90.0 # Smallest gap allowed between card slots, keeps scatter from overlapping
@export var vertical_jitter : float = 80.0 # How far up/down cards can randomly sit, tab-scatter feel

var card_default_z_index : int = hand_limit
var hand = self
var current_z_index : int
var card_default_transform : Transform2D
var card_default_rotation : float
var defaults_set : bool
var selected_card_idx : int
var currently_handling_card : bool
var card_map : Dictionary[Node2D, String]
var _rng := RandomNumberGenerator.new()

##------------------------------------------------------------------------

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	UpgradePoolManager.card_hand = self
	_draw_hand()

func _draw_hand() -> void:
	# TODO Needs to be changed to dynamically call which player lost, currently hard coded to p1
	var tres_file_paths = UpgradePoolManager._draw_from_pool(GameManager.p1_lose) # Gets an Array[String] of tres file paths
	current_z_index = card_default_z_index
	for _x in hand_limit:
		var upgarde_card = UPGRADE_CARD.instantiate()
		var tres_file = tres_file_paths.pop_front()
		print(tres_file)
		card_map.set(upgarde_card, tres_file)
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
	# Cards no longer rotate and no longer follow a fan curve. Each card gets
	# its own slot along hand_width so slots can't cross into each other,
	# then gets a small random x/y jitter inside that slot for a scattered,
	# desktop-tab look instead of a neat fan.
	_rng.randomize()
	var child_count = hand.get_child_count()
	var slot_width = hand_width / float(child_count)
	var max_jitter_x = max((slot_width - min_card_spacing) * 0.5, 0.0)
	
	for card in hand.get_children():
		var slot_index = card.get_index()
		var slot_center_x = (slot_index + 0.5) * slot_width - hand_width * 0.5
		var jitter_x = _rng.randf_range(-max_jitter_x, max_jitter_x)
		var jitter_y = _rng.randf_range(-vertical_jitter, vertical_jitter)
		
		var destination = hand.global_transform
		destination.origin.x += slot_center_x + jitter_x
		destination.origin.y += jitter_y
		
		# Sets the card locations the the assigned destinations
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "transform", destination, 0.4)
		await get_tree().create_timer(0.5).timeout
	
	hand.get_child(0).currently_highlighted = true
	hand.get_child(0)._handle_highlight()
	selected_card_idx = 0
	
func _input(event: InputEvent) -> void:
	# TODO handle fix for when inputting a movement action after selection has been made
	# Handles the input for the ui menu, god help us all
	
	# NOTE This handles the mouse input, scrapping this as I don't want to deal with clicking
	# NOTE Probably clean this up if we don't intend to actually use this
	#if event is InputEventMouseButton or event is InputEventMouseMotion:
		#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventKey:
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

	# NOTE This is for handling using a stick for controlling selection, I have abaondoned this as god has abandoned us
	# NOTE Probably clean this up if we don't intend to actually use this
	#elif event is InputEventJoypadMotion:
		#TODO handle controller stick selection, needs a cursor sprite
		#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	#else:
		#pass 
	
	# Handles selection input as it is
	if event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_A:
			if currently_handling_card == false:
				_handle_clicked_card()
	elif event is InputEventKey:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			if currently_handling_card == false:
				_handle_clicked_card()


func _handle_clicked_card():
	var highlighted_card : Node2D
	currently_handling_card = true
	for card in hand.get_children():
		if card.currently_highlighted == false:
			# card._handle_shader() # NOTE uncomment when shaders actually fucking work
			var tween = create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_property(card, "scale", Vector2(0.01, 0.01), 0.5)
			tween.parallel().tween_property(card, "modulate", Color.TRANSPARENT, 0.5)
			tween.tween_callback(card.queue_free)
			
		else:
			highlighted_card = card
	# Handles moving the selected card to the center of the screen,
	# can be changed to move to a specific node down the line
	highlighted_card.z_index = card_default_z_index + 1
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(highlighted_card, "transform", card_default_transform, 0.4)
	tween.parallel().tween_property(highlighted_card, "rotation", card_default_rotation, 0.4)
	tween.parallel().tween_property(highlighted_card, "scale", Vector2(2.0, 2.0), 0.4)
	# TODO to handle vfx if wanted or any other processes do so after the above code
	

	highlighted_card._handle_tres_file(card_map.get(highlighted_card), GameManager.p1_lose) # TODO needs to be changed to get the actual player that lost
