extends Node2D

# ──────────────────────────────────────────────────────────────────
#  CardHand (draft UI)
#
#  Fully signal-driven: waits for EventBus.upgrade_draft_ready, fired by
#  UpgradePoolManager after a round_lost, instead of pulling from the
#  pool manager directly. Doesn't care whether it's P1 or P2 drafting,
#  player_id comes in on the signal and rides straight through to the
#  eventual upgrade_picked emit.
#
#  Cards spawn tiny at the cardspawner marker (sitting on the folder
#  icon), pop out with a squash and stretch, then spread within the
#  bounds of the cardspawnarea collision shape.

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

@export var min_card_spacing : float = 70.0 # Smallest gap allowed between card slots, keeps scatter from overlapping
@export var vertical_jitter : float = 90.0 # How far up/down cards can randomly sit, tab-scatter feel
@export var highlighted_scale : float = 1.35 # How much bigger a card gets while it's the highlighted one
@export var highlight_tween_duration : float = 0.2
@export var initial_spread_delay : float = 0.5 # Pause after cards spawn before the spread starts
@export var card_stagger_delay : float = 0.5 # Delay between each card popping out of the folder
@export var card_travel_duration : float = 0.4 # How long a card takes to fly from the folder to its slot
@export var spawn_scale_fraction : float = 0.05 # How small a card is, relative to its normal size, right as it spawns
@export var squash_stretch_duration : float = 0.1 # Duration of each phase of the pop-out squash/stretch
@export var squash_scale_multiplier : Vector2 = Vector2(1.4, 0.6) # Wide and flat, right as the card pops out
@export var stretch_scale_multiplier : Vector2 = Vector2(0.7, 1.3) # Thin and tall, overshooting on the way to full size
@export var folder_node_path : NodePath = ^"../../taskbar/folder" # The folder sprite that bulges each time a card pops out
@export var folder_squash_stretch_duration : float = 0.08 # Kept snappier than the card's own squash/stretch, it's a smaller bulge
@export var folder_squash_scale_multiplier : Vector2 = Vector2(1.15, 0.85) # Wide and flat, the instant a card leaves it
@export var folder_stretch_scale_multiplier : Vector2 = Vector2(0.92, 1.1) # Thin and tall, settling back down after

@onready var hand : Node2D = self
@onready var cardspawner : Marker2D = $cardspawner
@onready var card_spawn_shape : CollisionShape2D = $cardspawnarea/CollisionShape2D
@onready var folder_sprite : Sprite2D = get_node(folder_node_path)

var folder_base_scale : Vector2
var current_player_id : int = 1
var card_default_z_index : int
var current_z_index : int
var card_default_transform : Transform2D
var card_default_rotation : float
var card_default_scale : Vector2
var defaults_set : bool
var selected_card_idx : int
var currently_handling_card : bool
var card_map : Dictionary[Node2D, UpgradeData]
var cards : Array[Node2D]
var _rng := RandomNumberGenerator.new()
# Edge-detection state for per-device input resolution (see _process below).
var _key_prev_state : Dictionary = {}
var _joy_button_prev_state : Dictionary = {}

##------------------------------------------------------------------------

func _ready() -> void:
	folder_base_scale = folder_sprite.scale
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
	card_default_z_index = offered.size() + 1
	current_z_index = card_default_z_index
	for upgrade in offered:
		var upgrade_card = UPGRADE_CARD.instantiate()
		card_map.set(upgrade_card, upgrade)
		cards.append(upgrade_card)
		if defaults_set != true:
			card_default_transform = upgrade_card.transform
			card_default_rotation = upgrade_card.rotation
			card_default_scale = upgrade_card.scale
			defaults_set = true

		add_child(upgrade_card)
		upgrade_card.set_upgrade(upgrade)
		upgrade_card.z_index = current_z_index
		current_z_index -= 1

		# Cards start out tiny and sitting on the folder, before they get
		# popped out and spread into the hand
		upgrade_card.position = cardspawner.position
		upgrade_card.rotation = card_default_rotation
		upgrade_card.scale = card_default_scale * spawn_scale_fraction

	await get_tree().create_timer(initial_spread_delay).timeout
	_spread_cards()


func _spread_cards() -> void:
	# Each card gets its own slot inside the spawn area's bounds so slots
	# can't cross into each other, then gets a small random x/y jitter
	# inside that slot for a scattered, desktop-tab look instead of a
	# neat fan.
	_rng.randomize()
	var spawn_bounds = _get_spawn_area_bounds()
	var slot_width = spawn_bounds.size.x / float(cards.size())
	var max_jitter_x = max((slot_width - min_card_spacing) * 0.5, 0.0)

	for slot_index in cards.size():
		var card = cards[slot_index]
		var slot_center_x = spawn_bounds.position.x + (slot_index + 0.5) * slot_width
		var jitter_x = _rng.randf_range(-max_jitter_x, max_jitter_x)
		var jitter_y = _rng.randf_range(-vertical_jitter, vertical_jitter)
		var destination = Vector2(slot_center_x + jitter_x, spawn_bounds.get_center().y + jitter_y)

		_pop_card_out_of_folder(card, destination)
		await get_tree().create_timer(card_stagger_delay).timeout

	cards[0].currently_highlighted = true
	cards[0]._handle_highlight()
	_tween_card_scale(cards[0], card_default_scale * highlighted_scale)
	selected_card_idx = 0


func _get_spawn_area_bounds() -> Rect2:
	# cardspawnarea's collision shape marks the region cards are allowed
	# to spread out into, so the draft stays on screen and away from the
	# folder icon it spawns out of. Everything here is in hand's local
	# space, same as cardspawner and the card nodes themselves.
	var rect_shape := card_spawn_shape.shape as RectangleShape2D
	var area_center = card_spawn_shape.get_parent().position + card_spawn_shape.position
	var half_size = rect_shape.size * 0.5
	return Rect2(area_center - half_size, rect_shape.size)


func _pop_card_out_of_folder(card: Node2D, destination: Vector2) -> void:
	# Flies the card from the folder to its hand slot while it squashes
	# and stretches back up to full size, like it's being flicked out
	var move_tween = create_tween()
	move_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(card, "position", destination, card_travel_duration)

	_play_squash_stretch(card, card_default_scale)
	_play_folder_squash_stretch()


func _play_squash_stretch(card: Node2D, target_scale: Vector2) -> void:
	var squash_scale = target_scale * squash_scale_multiplier
	var stretch_scale = target_scale * stretch_scale_multiplier

	var scale_tween = create_tween()
	scale_tween.tween_property(card, "scale", squash_scale, squash_stretch_duration)
	scale_tween.tween_property(card, "scale", stretch_scale, squash_stretch_duration)
	scale_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(card, "scale", target_scale, squash_stretch_duration)


func _play_folder_squash_stretch() -> void:
	# Same idea as the card's own pop, just smaller, so the folder looks
	# like it's bulging each time a card gets flicked out of it
	var squash_scale = folder_base_scale * folder_squash_scale_multiplier
	var stretch_scale = folder_base_scale * folder_stretch_scale_multiplier

	var scale_tween = create_tween()
	scale_tween.tween_property(folder_sprite, "scale", squash_scale, folder_squash_stretch_duration)
	scale_tween.tween_property(folder_sprite, "scale", stretch_scale, folder_squash_stretch_duration)
	scale_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(folder_sprite, "scale", folder_base_scale, folder_squash_stretch_duration)


func _tween_card_scale(card: Node2D, target_scale: Vector2) -> void:
	# Grows/shrinks a card's scale to reflect highlight state. Kept as its
	# own tween (rather than parallel on the move tween) since highlight
	# can change independently of position.
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", target_scale, highlight_tween_duration)


func _move_highlight(new_idx: int) -> void:
	# Shared by keyboard and joypad handling below - un-highlights and
	# shrinks the old card, then highlights and grows the new one.
	var old_card = cards[selected_card_idx]
	old_card.currently_highlighted = false
	old_card._handle_highlight()
	_tween_card_scale(old_card, card_default_scale)

	selected_card_idx = new_idx
	var new_card = cards[selected_card_idx]
	new_card.currently_highlighted = true
	new_card._handle_highlight()
	_tween_card_scale(new_card, card_default_scale * highlighted_scale)


# ── Per-device input resolution ──
# Mirrors player_select.gd: the selecting player is the PlayerInputDevice
# claimed for current_player_id during Player Select, so navigation and
# confirm route to the actual loser's device (WASD / arrows / a specific
# controller) rather than a hardcoded key set or an unfiltered joypad.

func _current_device() -> PlayerInputDevice:
	if current_player_id == 1:
		return GameManager.p1_device
	return GameManager.p2_device


func _device_just_pressed(device: PlayerInputDevice, action_name: String) -> bool:
	if device == null:
		return false
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return _keyboard_action_just_pressed(action_name, device.native_action_suffix)
	return _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name))


func _keyboard_action_just_pressed(base: String, suffix: String) -> bool:
	var just_pressed := false
	var keys: Array = GameManager.keyboard_layouts.get(suffix, {}).get(base, [])
	for event in keys:
		if not (event is InputEventKey):
			continue
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode
		var pressed: bool
		if code != KEY_NONE:
			pressed = Input.is_physical_key_pressed(code)
		else:
			code = key_event.keycode
			if code == KEY_NONE:
				continue
			pressed = Input.is_key_pressed(code)
		var was_pressed: bool = _key_prev_state.get(code, false)
		_key_prev_state[code] = pressed
		if pressed and not was_pressed:
			just_pressed = true
	return just_pressed


func _joy_button_for_action(action_name: String) -> int:
	match action_name:
		"Left":
			return JOY_BUTTON_DPAD_LEFT
		"Right":
			return JOY_BUTTON_DPAD_RIGHT
		_:
			return JOY_BUTTON_A


func _joy_button_just_pressed(device_id: int, button_index: int) -> bool:
	var key := "%d_%d" % [device_id, button_index]
	var pressed := Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed: bool = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed


func _process(_delta: float) -> void:
	# Once a card's been picked and the rest are queue_free()-ing, don't
	# let navigation touch them (the old out-of-bounds crash).
	if currently_handling_card or cards.is_empty():
		return

	var device := _current_device()
	if device == null:
		return

	# Bound against the hand's actual current card count rather than a
	# fixed hand_limit, so this can't overshoot on a short hand.
	var last_idx = cards.size() - 1

	if _device_just_pressed(device, "Left"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if selected_card_idx > 0:
			_move_highlight(selected_card_idx - 1)
	elif _device_just_pressed(device, "Right"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if selected_card_idx < last_idx:
			_move_highlight(selected_card_idx + 1)

	if _device_just_pressed(device, "Normal"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_handle_clicked_card()


func _handle_clicked_card():
	var highlighted_card : Node2D
	currently_handling_card = true
	for card in cards:
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
	tween.tween_property(highlighted_card, "position", card_default_transform.origin, 0.4)
	tween.parallel().tween_property(highlighted_card, "rotation", card_default_rotation, 0.4)
	tween.parallel().tween_property(highlighted_card, "scale", Vector2(3.0, 3.0), 0.4)

	highlighted_card._handle_upgrade(card_map.get(highlighted_card), current_player_id)
