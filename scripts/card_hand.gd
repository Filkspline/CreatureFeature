extends Node2D

# ──────────────────────────────────────────────────────────────────
#  CardHand (draft UI)
#
#  Fully signal-driven: waits for EventBus.upgrade_draft_ready, fired by
#  UpgradePoolManager after a round_lost, instead of pulling from the
#  pool manager directly. Doesn't care whether it's P1 or P2 drafting —
#  player_id comes in on the signal and rides straight through to the
#  eventual upgrade_picked emit.

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

@export var hand_width : float = 500
@export var min_card_spacing : float = 90.0 # Smallest gap allowed between card slots, keeps scatter from overlapping
@export var vertical_jitter : float = 80.0 # How far up/down cards can randomly sit, tab-scatter feel

var hand = self
var current_player_id : int = 1
var card_default_z_index : int
var current_z_index : int
var card_default_transform : Transform2D
var card_default_rotation : float
var defaults_set : bool
var selected_card_idx : int
var currently_handling_card : bool
var card_map : Dictionary[Node2D, UpgradeData]
var _rng := RandomNumberGenerator.new()

##------------------------------------------------------------------------

func _ready() -> void:
	EventBus.upgrade_draft_ready.connect(_on_upgrade_draft_ready)
	# Handles the normal case: round_lost fires (and UpgradePoolManager
	# draws the cards) BEFORE this scene finishes loading, since whoever
	# decides the round ended calls change_scene_to_file right after
	# emitting. That signal is gone by the time we get here, so check for
	# an already-drawn offer directly instead of only listening for one.
	if UpgradePoolManager.last_offer_player_id != -1:
		_on_upgrade_draft_ready(UpgradePoolManager.last_offer_player_id, UpgradePoolManager.last_offer)


func _on_upgrade_draft_ready(player_id: int, offered: Array[UpgradeData]) -> void:
	current_player_id = player_id
	_draw_hand(offered)


func _draw_hand(offered: Array[UpgradeData]) -> void:
	card_default_z_index = offered.size()
	current_z_index = card_default_z_index
	for upgrade in offered:
		var upgarde_card = UPGRADE_CARD.instantiate()
		card_map.set(upgarde_card, upgrade)
		if defaults_set != true:
			card_default_transform = upgarde_card.transform
			card_default_rotation = upgarde_card.rotation
			defaults_set = true
		
		add_child(upgarde_card)
		upgarde_card.set_upgrade(upgrade)
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
	# Once a card's been picked and the rest are queue_free()-ing, don't let
	# navigation touch them — this was the out-of-bounds crash from before.
	if currently_handling_card:
		return
	if hand.get_child_count() == 0:
		return
	
	# Bound against the hand's actual current child count rather than a
	# fixed hand_limit, so this can't overshoot if fewer cards were
	# offered than expected, or a card's already been freed.
	var last_idx = hand.get_child_count() - 1

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
			if selected_card_idx == last_idx:
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
			if selected_card_idx == last_idx:
				pass
			else:
				selected_card_idx += 1
				hand.get_child(selected_card_idx).currently_highlighted = true
				hand.get_child(selected_card_idx)._handle_highlight()

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
	
	highlighted_card._handle_upgrade(card_map.get(highlighted_card), current_player_id)
