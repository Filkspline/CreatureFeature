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
## Where the draft hands off once both steps are done.
const FIGHT_SCENE := "res://scenes/test_level.tscn"

## The draft runs in two steps for the player who lost the round: the
## special-move cards first (where keeping the special already equipped is
## always an option), then the normal cards.
enum DraftStep { SPECIAL, NORMAL }

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

## Spacing, in z_index, between one card's whole layer band and the next
## card's. A single card spreads its own layers across four z values (its
## art layer, its frame, its back, and the back's dark edge copy), so two
## cards only one z apart interleave: the lower card's border ends up drawn
## across the upper card's art. Any value at or above that spread works,
## this is just a round number with headroom.
@export var card_z_step : int = 10
## z_index of the oldest card in the owned-cards stack. Owned cards climb
## from here in pick order, newest on top of the stack, and the offered
## hand is stacked above the whole owned stack so the pickable cards always
## read as the foreground. Keep this above the draft scene's backdrop
## (background and taskbar sit at z_index -10 in upgrade_card_ui.tscn).
@export var owned_card_z_base : int = 10
## Beat between a card being confirmed and the draft moving on, either into
## the second step or, once both steps are done, into the level. Long
## enough for the pick animation to read.
@export var pick_settle_delay : float = 0.75

## How far apart (in local y) each already-owned card sits from the next
## in the owned-cards stack. Positive moves each newer card down the
## screen from the previous one.
@export var owned_card_vertical_offset : float = 50.0
## Scale applied to owned-card displays, relative to the normal card
## scale, so the "already have this" stack still reads clearly at a
## glance without being as large as the actual pickable hand.
@export var owned_card_scale_fraction : float = 0.85
## Pause after the draft screen opens before the owned-card reveal
## starts, so the reveal isn't swallowed by the scene transition's wipe.
@export var owned_card_reveal_start_delay : float = 0.45
## How long each owned card takes to pop in at the marker before it
## flips. The flip starts once this finishes.
@export var owned_card_appear_duration : float = 0.18
## Gap between one owned card finishing its flip and the next one
## appearing, so the stack reads as a one-by-one reveal.
@export var owned_card_flip_stagger_delay : float = 0.12

@onready var hand : Node2D = self
@onready var cardspawner : Marker2D = $cardspawner
@onready var card_spawn_shape : CollisionShape2D = $cardspawnarea/CollisionShape2D
@onready var folder_sprite : Sprite2D = get_node(folder_node_path)
@onready var owned_cards_marker : Marker2D = $ownedcards
# The draft heading lives outside the hand (a sibling of the Camera2D this
# node sits under), so look it up by path rather than assuming it's a child.
@onready var title_label : Label = get_node_or_null("../../title_label")

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
# Both steps' offers, drawn from the pool up front (see UpgradePoolManager)
# and consumed one step at a time below.
var _special_offer : Array[UpgradeData]
var _normal_offer : Array[UpgradeData]
## Which step the hand is currently showing.
var _step : DraftStep = DraftStep.SPECIAL
# Purely-display cards for the "already owned" stack. Kept separate from
# `cards` so they're never touched by highlight navigation, input
# handling, or the picking/discard flow in _handle_clicked_card().
var owned_cards : Array[Node2D]
var _rng := RandomNumberGenerator.new()
# Edge-detection state for per-device input resolution (see _process below).
var _key_prev_state : Dictionary = {}
var _joy_button_prev_state : Dictionary = {}
var _joy_axis_prev_state : Dictionary = {}

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
		_on_upgrade_draft_ready(
			UpgradePoolManager.last_offer_player_id,
			UpgradePoolManager.last_special_offer,
			UpgradePoolManager.last_offer
		)


func _on_upgrade_draft_ready(player_id: int, special_offer: Array[UpgradeData], normal_offer: Array[UpgradeData]) -> void:
	current_player_id = player_id
	_special_offer = special_offer
	_normal_offer = normal_offer
	_update_title_label(player_id)
	_draw_step(DraftStep.SPECIAL)
	# The owned stack is drawn once for the whole draft, not per step: it
	# lists what this player walked in with, and re-revealing it between
	# steps would replay the whole flip sequence over the second hand.
	_draw_owned_cards(player_id)


# Draws one step's hand. Falls through to the next step when a step has
# nothing to offer (an exhausted pool), and leaves the draft when there is
# nothing left at all, so the draft can never strand the player on an empty
# hand with no way forward.
func _draw_step(step: DraftStep) -> void:
	var offered := _offer_for(step)
	if offered.is_empty():
		if step == DraftStep.SPECIAL:
			_draw_step(DraftStep.NORMAL)
		else:
			_leave_draft()
		return

	_step = step
	_clear_hand()
	_update_title_label(current_player_id)
	_draw_hand(offered)


func _offer_for(step: DraftStep) -> Array[UpgradeData]:
	return _special_offer if step == DraftStep.SPECIAL else _normal_offer


# Frees whatever is left of the previous step's hand and resets the hand
# bookkeeping, so the next step starts from a clean slate. The card that was
# just picked is still flying to the centre when this runs, so it goes too.
func _clear_hand() -> void:
	for card in cards:
		if is_instance_valid(card):
			card.queue_free()
	cards.clear()
	card_map.clear()
	selected_card_idx = 0
	currently_handling_card = false


# Hands out the z bands for one draft, before anything spawns. The offered
# hand sits above the entire owned stack, and each stack climbs by
# card_z_step, so neither stack can drift into the other's range however
# many cards it holds. The first offered card still gets the highest band,
# same as before, so it stays the one drawn on top of the fan.
func _assign_card_z_bands(offered_count: int, owned_count: int) -> void:
	var hand_z_base : int = owned_card_z_base + (owned_count + 1) * card_z_step
	card_default_z_index = hand_z_base + maxi(offered_count - 1, 0) * card_z_step
	current_z_index = card_default_z_index


# The picked-upgrade list for a player, in pick order (oldest first). Read
# here and in _draw_owned_cards so the z bands and the spawned cards can
# never disagree about how many owned cards there are.
func _owned_upgrade_paths(player_id: int) -> Array:
	var picked : Array = UpgradePoolManager.current_upgrades.get(player_id, [])
	return picked


# Says which player is actually drafting, and which of the draft's two steps
# they are on. Only the round's loser picks, and it isn't otherwise obvious
# from the screen who that is or why the second hand appeared.
func _update_title_label(player_id: int) -> void:
	if not title_label:
		return
	if _step == DraftStep.SPECIAL and not _special_offer.is_empty():
		title_label.text = "PLAYER %d: CHOOSE YOUR SPECIAL" % player_id
	else:
		title_label.text = "PLAYER %d: SELECT YOUR UPGRADES" % player_id


func _draw_hand(offered: Array[UpgradeData]) -> void:
	# Recomputed per step rather than once per draft: the two steps can
	# offer different numbers of cards, and the bands have to clear the
	# owned stack either way.
	_assign_card_z_bands(offered.size(), _owned_upgrade_paths(current_player_id).size())
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
		current_z_index -= card_z_step

		# Cards start out tiny and sitting on the folder, before they get
		# popped out and spread into the hand
		upgrade_card.position = cardspawner.position
		upgrade_card.rotation = card_default_rotation
		upgrade_card.scale = card_default_scale * spawn_scale_fraction

	await get_tree().create_timer(initial_spread_delay).timeout
	_spread_cards()


# Shows every card this player has already picked so far this match,
# stacked at owned_cards_marker with a vertical offset per card. Cards are
# revealed strictly one at a time, oldest first: each one pops in at the
# marker, plays its flip-to-face-up animation, and only then does the next
# one appear.
#
# Purely a display: these never enter `cards`, they're flagged
# is_display_only so the hand's highlight sweep skips them, and input
# handling / _handle_clicked_card()'s pick-discard flow never touch them.
func _draw_owned_cards(player_id: int) -> void:
	_clear_owned_cards()

	var picked: Array = _owned_upgrade_paths(player_id)
	if picked.is_empty():
		return

	# Let the scene transition's wipe clear first, otherwise the whole
	# reveal plays out behind a closed mouth and is never actually seen.
	if owned_card_reveal_start_delay > 0.0:
		await get_tree().create_timer(owned_card_reveal_start_delay).timeout

	var index := 0
	for path in picked:
		var upgrade: UpgradeData = load(path)
		if upgrade == null:
			continue

		var owned_card := _spawn_owned_card(upgrade, index)
		index += 1
		if owned_card == null:
			continue
		await _reveal_owned_card(owned_card)

		if owned_card_flip_stagger_delay > 0.0:
			await get_tree().create_timer(owned_card_flip_stagger_delay).timeout


# Creates one owned-card display at its stack slot and pops it in, inside
# its own z band.
#
# Sibling order on its own is not enough to order these: a card's layers do
# not all sit at its base z (the art is two below the frame, the back is
# one above it, see the face-z comment in upgrade_card.gd), so two cards
# sharing a base z interleave and the older card's border draws across the
# newer card's art. Giving each card a band card_z_step wide, climbing in
# pick order, means the newer card has every one of its layers above every
# layer of the older one, which is the same newest-on-top result sibling
# order was reaching for, just without the interleaving.
func _spawn_owned_card(upgrade: UpgradeData, index: int) -> Node2D:
	var owned_card := UPGRADE_CARD.instantiate() as Node2D
	if not owned_card:
		return null
	# Keeps this copy out of the hand's highlight/selection sweep.
	owned_card.is_display_only = true
	add_child(owned_card)
	owned_card.set_upgrade(upgrade)
	owned_card.z_index = owned_card_z_base + index * card_z_step

	var base_scale = card_default_scale if defaults_set else owned_card.scale
	var target_scale = base_scale * owned_card_scale_fraction
	owned_card.rotation = 0.0
	owned_card.position = owned_cards_marker.position + Vector2(0, index * owned_card_vertical_offset)
	owned_card.scale = target_scale * spawn_scale_fraction

	var appear_tween = create_tween()
	appear_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	appear_tween.tween_property(owned_card, "scale", target_scale, owned_card_appear_duration)

	owned_cards.append(owned_card)
	return owned_card


# Waits for one owned card to finish popping in, flips it, then waits for
# that flip to actually finish before returning. This is what makes the
# reveal sequential instead of everything happening in the same frame.
func _reveal_owned_card(owned_card: Node2D) -> void:
	if not is_instance_valid(owned_card):
		return
	if owned_card_appear_duration > 0.0:
		await get_tree().create_timer(owned_card_appear_duration).timeout
	if not is_instance_valid(owned_card):
		return
	owned_card.flip_card()
	await owned_card.card_flip_finished


func _clear_owned_cards() -> void:
	for card in owned_cards:
		if is_instance_valid(card):
			card.queue_free()
	owned_cards.clear()


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
		# A step change can clear this hand while the stagger below is still
		# running, so anything already freed is skipped rather than tweened.
		if not is_instance_valid(card):
			continue
		var slot_center_x = spawn_bounds.position.x + (slot_index + 0.5) * slot_width
		var jitter_x = _rng.randf_range(-max_jitter_x, max_jitter_x)
		var jitter_y = _rng.randf_range(-vertical_jitter, vertical_jitter)
		var destination = Vector2(slot_center_x + jitter_x, spawn_bounds.get_center().y + jitter_y)

		_pop_card_out_of_folder(card, destination)
		await get_tree().create_timer(card_stagger_delay).timeout

	if cards.is_empty() or not is_instance_valid(cards[0]):
		return
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
	# A controller can answer with either the d-pad/button bound to this
	# base or the left stick pushed in that direction. Both are checked,
	# because reading only buttons here meant the stick did nothing on this
	# screen while it worked fine in the fight.
	if _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name)):
		return true
	return _joy_axis_just_pressed(device.device_id, action_name)


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
		"Up":
			return JOY_BUTTON_DPAD_UP
		"Down":
			return JOY_BUTTON_DPAD_DOWN
		_:
			return JOY_BUTTON_A


func _joy_button_just_pressed(device_id: int, button_index: int) -> bool:
	var key := "%d_%d" % [device_id, button_index]
	var pressed := Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed: bool = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed


# Stick equivalent of a d-pad press for the directional bases, edge detected
# the same way the button checks above are. The axis map and threshold are
# GameManager's, so this screen and player select agree on what the stick
# means and how far it has to travel.
func _joy_axis_just_pressed(device_id: int, action_name: String) -> bool:
	var binding: Array = GameManager.JOY_AXIS_BASES.get(action_name, [])
	if binding.is_empty():
		return false
	var axis: int = binding[0]
	var direction: float = binding[1]
	var pressed := Input.get_joy_axis(device_id, axis) * direction >= GameManager.JOY_AXIS_DEADZONE
	var key := "%d_%d_%s" % [device_id, axis, direction]
	var was_pressed: bool = _joy_axis_prev_state.get(key, false)
	_joy_axis_prev_state[key] = pressed
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
	# One band above the top of the fan, so the picked card's whole stack
	# (art included) clears every other card while it flies out.
	highlighted_card.z_index = card_default_z_index + card_z_step
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(highlighted_card, "position", card_default_transform.origin, 0.4)
	tween.parallel().tween_property(highlighted_card, "rotation", card_default_rotation, 0.4)
	tween.parallel().tween_property(highlighted_card, "scale", Vector2(3.0, 3.0), 0.4)

	_resolve_pick(card_map.get(highlighted_card))


# A pick was confirmed. This is where the draft's two steps are sequenced:
# step one always leads into step two, step two ends the draft, and a pick
# that keeps the special already equipped skips the pool entirely.
func _resolve_pick(upgrade : UpgradeData) -> void:
	if upgrade == null:
		print("[TRACE] draft pick | player=%d | no upgrade mapped to the picked card" % current_player_id)
		_leave_draft()
		return

	if _is_keep_special_pick(upgrade):
		# Deliberately not emitted: keeping the special you walked in with
		# costs nothing, records nothing, and leaves the pool alone, so the
		# same card can still be offered in a later round.
		print("[TRACE] draft keep | player=%d kept special '%s' (free, pool untouched)"
			% [current_player_id, upgrade.name])
	else:
		# UpgradePoolManager listens for this: it records the pick and takes
		# it out of the pool. Applying happens later, when the next Player
		# registers in the level.
		EventBus.upgrade_picked.emit(current_player_id, upgrade)

	if pick_settle_delay > 0.0:
		await get_tree().create_timer(pick_settle_delay).timeout

	if _step == DraftStep.SPECIAL:
		_draw_step(DraftStep.NORMAL)
	else:
		_leave_draft()


# True when this pick is the special the player already has equipped. Only
# meaningful in step one; the same card picked out of the pool counts too,
# since it means the same thing (keep what I have), which is why the pool
# manager doesn't need to add a second copy of it to the hand. Compared by
# move_name, the identity the rest of the project uses for moves.
func _is_keep_special_pick(upgrade : UpgradeData) -> bool:
	if _step != DraftStep.SPECIAL or upgrade.unlocked_move == null:
		return false
	var current := GameManager.get_selected_special(current_player_id)
	return current != null and upgrade.unlocked_move.move_name == current.move_name


func _leave_draft() -> void:
	# Routed through SceneTransition (mouth wipe) instead of a raw
	# change_scene_to_file, same as every other scene change in the project.
	SceneTransition.change_scene(FIGHT_SCENE)
