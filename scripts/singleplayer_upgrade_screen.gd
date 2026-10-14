extends CanvasLayer

# Used for _dbg
var script_id = "SP Upgrade"

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

## The card's own flip-to-face-up animation, used to time an equipped card's
## reveal against the real animation rather than a guessed duration.
const FLIP_ANIM := "card_flip"

# Focus rows. Three of them: the two card rows, then the Back button, so a
# player on a pad can always reach the way out with the same up/down they
# already use for the cards.
const ROW_UNLOCKS := 0
const ROW_UPGRADES := 1
const ROW_BACK := 2
const ROW_COUNT := 3

## The key that closes the practice menu again. Opening uses the whole
## UpgradeMenuToggle action (Tab, Enter, pad Y); closing is this key or the
## on-screen Back button. See _test_toggle_menu() for why Enter is not a close
## key.
const MENU_CLOSE_KEY := KEY_TAB

# Handling the nodes in the UI
@onready var player_moves_node = $move_node
@onready var player_stats_node = $upgrade_node
@onready var back_button : Button = $BackButton
@onready var focus_emphasis : MenuFocusEmphasis = get_node_or_null("MenuFocusEmphasis")

# The training dummy this menu drives. Wired in the scene as a NodePath, so
# which node it points at is editable rather than hardcoded. Typed as Node2D
# and called dynamically: the practice menu only needs the dummy's own methods,
# so it does not have to depend on the Dummy class being registered globally.
@export var dummy_path: NodePath = ^"../dummy"
@onready var dummy: Node2D = get_node_or_null(dummy_path)

# Where the equipped-card row is laid out. Points at the anchor inside the
# tutorial background, so the row lives on that background rather than in this
# menu - it stays on screen while the menu is closed.
@export var equipped_cards_anchor : Node2D

# Card visual variables ----------------------------------------------------------------------------
# Handles all the info for tweens and flipping the cards for visual flair
@export var base_card_scale_multiplier : float = 1.0 # cards read bigger here than in the mid round draft
## Extra growth on the focused card, on top of the card's own highlight tween.
## Left at 1.0 by default because a highlighted UpgradeCard already scales
## itself up (upgrade_card.gd's HOVER_MULTIPLIER): doing it in both places
## double-scaled the focused card and pushed its neighbours under it.
@export var focused_extra_scale : float = 1.0
@export var scale_falloff_per_step : float = 0.18 # how much smaller each card gets per slot away from focus
@export var min_card_scale_fraction : float = 0.52
@export var alpha_falloff_per_step : float = 0.28 # how much more transparent each card gets per slot away from focus
@export var min_card_alpha : float = 0.15
## How far down the row a card is faded when its row is not the focused one.
@export var inactive_row_alpha : float = 0.45
## Horizontal distance between adjacent card slots. Must clear the focused
## card's own width or the row reads as one overlapping smear.
@export var card_step_spacing : float = 96.0
@export var max_rendered_offset : int = 2 # cards further than this from focus are hidden outright
@export var card_move_duration : float = 0.18
@export var owned_card_z_base : int = 10
@export var card_z_step : int = 10
## How big an equipped card is, as a fraction of the card scene's own scale.
@export var owned_card_scale_fraction : float = 0.85
## Horizontal gap between equipped cards, before the row is squeezed to fit.
@export var equipped_card_spacing : float = 62.0
## Width the equipped row has to fit inside. Set from the tutorial background's
## card area; the cards shrink and close up to honour it.
@export var equipped_row_width : float = 176.0
## Pixels of the idle float's cycle that alternating equipped cards start
## part-way through, so the row breathes instead of bobbing in lockstep.
@export var equipped_card_bob_phase : float = 3.0
@export var spawn_scale_fraction : float = 0.05
@export var owned_card_appear_duration : float = 0.18
@export var owned_card_flip_stagger_delay : float = 0.0
## Only used if a card has no flip animation to read a length from.
@export var fallback_flip_seconds : float = 0.45
var card_default_scale : Vector2
## A card face's width in pixels at card_default_scale, measured off the card
## scene the first time one is built rather than hardcoded, so re-exporting the
## card art cannot silently break the equipped row's fit.
var card_art_width : float = 0.0

# Menu handling ------------------------------------------------------------------------------------
var menu_open : bool = false
## Previous state of the close key, for the hand-rolled edge in
## _test_toggle_menu().
var _close_key_was_down : bool = false

# Card storage -------------------------------------------------------------------------------------
# Handles the data storage for the active cards the player has picked
var selected_cards = []

# Column handling ----------------------------------------------------------------------------------
# Handles all the information regarding the rows built for the cards in the menu as well as the
# scrolling and selection
class UpgradeColumn:
	var anchor : Node2D
	var wrappers : Array[CanvasGroup] = []
	var cards : Array[Node2D] = []
	var upgrade_map : Dictionary[Node2D, UpgradeData] = {}
	var focus_index : int = 0
	var locked : bool = false
	## True while this row is the one the selector is on. An inactive row stays
	## dimmer and its focused card gives up the selector icon and the scale-up.
	var is_active : bool = false

var p1_selection_column : int = 0 # 0 for unlocks, 1 for upgrades, 2 for the Back button
# Edge-detection state for per-device input resolution.
var _key_prev_state : Dictionary = {}
var _joy_button_prev_state : Dictionary = {}
var _joy_axis_prev_state : Dictionary = {}
var unlock : UpgradeColumn
var upgrade : UpgradeColumn


# Scripts ------------------------------------------------------------------------------------------
func _dbg(msg: String) -> void:
	if GameManager.debug:
		print_rich("[%s] %s" % [script_id, msg])


func _ready() -> void:
	if not GameManager.return_singleplayer_upgrade_arrays.is_connected(_on_recieve_arrays):
		GameManager.return_singleplayer_upgrade_arrays.connect(_on_recieve_arrays) # Connects to the signal that returns all the arrays with the upgrade data
	GameManager.request_singleplayer_upgrade_arrays.emit() # Emits the signal to request the arrays for the upgrade data
	self.hide()

	# Cycling is permanent: the dummy changes its own block state on a timer and
	# nothing here turns that off, so the practice menu has no cycling toggle to
	# keep in step. Pushed here as well as authored on the dummy so a level that
	# saved the dummy with cycling off still ends up cycling.
	if dummy:
		dummy.set_cycling(true)

	# The Back button is a real Button, so it uses real focus: the emphasis node
	# and the button's own focus style do the highlighting, the same way the
	# main menu and the pause menu do it.
	if focus_emphasis and back_button:
		focus_emphasis.register_buttons([back_button])


func _process(_delta: float) -> void:
	# A frame that opens or closes the menu never also acts on a card. Enter is
	# both the menu key and the confirm key, so without this the one press would
	# open the menu and immediately take whatever card happened to be focused.
	if _test_toggle_menu():
		return
	if not menu_open:
		return
	_handle_player_input(1)


func _test_toggle_menu() -> bool:
	# The close key's edge is tracked by hand rather than read as an action,
	# because it deliberately is not the whole UpgradeMenuToggle action: Enter is
	# part of that action and is also the confirm key for the focused card
	# (ui_accept). A real open/close toggle on Enter would mean a press with the
	# menu open always closed it first, and a card could never be taken with
	# Enter at all. So Enter opens and confirms; Tab opens and closes; the Back
	# button is the way out on a pad.
	var close_down := Input.is_physical_key_pressed(MENU_CLOSE_KEY)
	var close_just_pressed := close_down and not _close_key_was_down
	_close_key_was_down = close_down

	if not menu_open:
		if Input.is_action_just_pressed("UpgradeMenuToggle"):
			pause()
			return true
		return false

	if close_just_pressed:
		resume()
		return true
	return false


func resume() -> void:
	GameManager.player_input_locked = false
	hide()
	menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_apply_selected_upgrades()

func pause() -> void:
	show()
	GameManager.player_input_locked = true
	menu_open = true
	# The mouse is shown while the menu is up so the Back button can be clicked.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.sp_player_upgrade_reset.emit()
	_refresh_row_focus()


# ── Picking cards ──

func _select_card(column_index : int) -> void:
	var data := _focused_card_data(_get_column(column_index))
	if data == null:
		return
	if selected_cards.has(data):
		_remove_card(data)
		return
	selected_cards.append(data)
	SfxManager.play_ui_select()
	_dbg("[SELECT CARD] Current card array: %s" % [selected_cards])
	_draw_owned_cards()


# Special takes the focused card back off again. Same public path the confirm
# button uses, so the two can never disagree about what is equipped.
func _deselect_focused() -> void:
	var data := _focused_card_data(_get_column(_focused_row()))
	if data == null or not selected_cards.has(data):
		return
	_remove_card(data)


func _remove_card(upgrade : UpgradeData) -> void:
	var index := selected_cards.find(upgrade)
	if index == -1:
		return
	selected_cards.remove_at(index)
	SfxManager.play_ui_hover()
	_dbg("[DESELECT CARD] Current card array: %s" % [selected_cards])
	_draw_owned_cards()


func _apply_selected_upgrades() -> void:
	for upgrade in selected_cards:
		if upgrade == null:
			continue
		if GameManager.p1_node == null:
			_dbg("[color=red][UPGRADE APPLICATION] No p1_node registered, skipping")
			return
		_dbg("[UPGRADE APPLICATION] Applied upgrade: %s" % upgrade)
		upgrade.apply_to(GameManager.p1_node)


# --------------------------------------------------------------------------------------------------
# Handling building the columns and card tweens

func _build_column(anchor : Node2D, upgrades : Array[UpgradeData], row : int) -> UpgradeColumn:
	var column := UpgradeColumn.new()
	column.anchor = anchor

	for upgrade in upgrades:
		var card = UPGRADE_CARD.instantiate()
		var wrapper := CanvasGroup.new()
		wrapper.add_child(card)

		anchor.add_child(wrapper)
		anchor.move_child(wrapper, 0) # keep lock_frame drawing on top of the cards

		# Captured once from the card scene itself, and read after it is in the
		# tree: the card's own node references are @onready, so they are null
		# until then. This was never set at all, so every owned-card display was
		# built at zero scale and invisible - the reason the owned-card stack
		# "did not work".
		if card_default_scale == Vector2.ZERO:
			card_default_scale = card.scale
		if card_art_width <= 0.0 and card.card_front and card.card_front.texture:
			card_art_width = float(card.card_front.texture.get_width()) * card.card_control.scale.x * card_default_scale.x

		card.set_upgrade(upgrade)
		card.flip_card()
		card.show()

		column.wrappers.append(wrapper)
		column.cards.append(card)
		column.upgrade_map.set(card, upgrade)

	column.is_active = _focused_row() == row
	_apply_focus_marker(column, column.focus_index, column.is_active)
	return column


func _layout_column(column : UpgradeColumn, animate : bool) -> void:
	for i in column.wrappers.size():
		var offset = i - column.focus_index
		var wrapper = column.wrappers[i]

		if absi(offset) > max_rendered_offset:
			wrapper.visible = false
			continue

		wrapper.visible = true
		wrapper.z_index = max_rendered_offset - absi(offset)

		var target_position = Vector2(offset * card_step_spacing, 0.0)
		var target_scale = _card_scale_for_offset(offset, column.is_active)
		var target_alpha = _card_alpha_for_offset(offset, column.is_active)

		if animate:
			_tween_card(wrapper, target_position, target_scale, target_alpha)
		else:
			wrapper.position = target_position
			wrapper.scale = target_scale
			wrapper.modulate.a = target_alpha


func _card_scale_for_offset(offset : int, is_active : bool) -> Vector2:
	var step_penalty = scale_falloff_per_step * absi(offset)
	# Only the active row's focused card gets the extra size; a highlighted
	# UpgradeCard also scales itself up by HOVER_MULTIPLIER, so the two together
	# are what the focused card actually reads as.
	var extra = focused_extra_scale if (offset == 0 and is_active) else 1.0
	var scale_fraction = maxf(min_card_scale_fraction, extra - step_penalty)
	return Vector2.ONE * base_card_scale_multiplier * scale_fraction


func _card_alpha_for_offset(offset : int, is_active : bool) -> float:
	var alpha = 1.0 - alpha_falloff_per_step * absi(offset)
	if not is_active:
		alpha = minf(alpha, inactive_row_alpha)
	return maxf(min_card_alpha, alpha)


func _tween_card(wrapper : CanvasGroup, target_position : Vector2, target_scale : Vector2, target_alpha : float) -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(wrapper, "position", target_position, card_move_duration)
	tween.tween_property(wrapper, "scale", target_scale, card_move_duration)
	tween.tween_property(wrapper, "modulate:a", target_alpha, card_move_duration)


func _on_recieve_arrays(move_array : Array[UpgradeData], upgrade_array : Array[UpgradeData]) -> void:
	unlock = _build_column(player_moves_node, move_array, ROW_UNLOCKS)
	upgrade = _build_column(player_stats_node, upgrade_array, ROW_UPGRADES)

	_layout_column(unlock, false)
	_layout_column(upgrade, false)
	_refresh_row_focus()


# Menu input handling ------------------------------------------------------------------------------
# Handles the logic for player input while in the upgrade menu as well as the logic for cycling
# between rows. Input is resolved through the device that claimed player 1, the way every other menu
# does it, instead of reading the raw "UpP1"/"NormalP1" actions.
func _handle_player_input(player_id : int) -> void:
	var device := _current_device()

	if _device_just_pressed(device, "Up"):
		_switch_active_column(-1)
	elif _device_just_pressed(device, "Down"):
		_switch_active_column(1)
	elif _device_just_pressed(device, "Left"):
		_adjust_focused(-1)
	elif _device_just_pressed(device, "Right"):
		_adjust_focused(1)
	elif _device_just_pressed(device, "Special"):
		_deselect_focused()
	elif _confirm_pressed(device):
		_confirm_focused()


# Enter also confirms, so a keyboard player never has to work out which of the
# configured buttons is theirs. Only for a keyboard device, since ui_accept
# answers to a pad's A as well and would double up with the device check.
#
# Enter specifically, not the whole ui_accept action: ui_accept also answers to
# Space, which is the keyboard's Jump button, so a card should not be taken
# because someone pressed jump out of habit with the menu open. Requiring the
# Enter key to be down as well as the action to have just fired keeps the edge
# detection (no extra state) while ignoring Space.
func _confirm_pressed(device: PlayerInputDevice) -> bool:
	if _device_just_pressed(device, "Normal"):
		return true
	if device == null or device.kind != PlayerInputDevice.Kind.KEYBOARD:
		return false
	return Input.is_action_just_pressed("ui_accept") and Input.is_physical_key_pressed(KEY_ENTER)


# Practice Range is player 1's screen, so it follows player 1's device. Opened
# without the select screen (running the lab scene straight from the editor),
# nobody has claimed a device and every per-device check below would quietly
# answer "no", which reads as a broken menu rather than an unconfigured one.
# The fallback is the WASD layout, the same one such a session's player would be
# driving anyway.
func _current_device() -> PlayerInputDevice:
	if GameManager.p1_device != null:
		return GameManager.p1_device
	return PlayerInputDevice.make_keyboard("Keyboard (WASD)", "P1")


func _focused_row() -> int:
	return p1_selection_column


func _adjust_focused(direction : int) -> void:
	var column := _get_column(_focused_row())
	if column == null or column.locked or column.cards.is_empty():
		return
	_cycle_column(column, direction)


func _confirm_focused() -> void:
	if _focused_row() == ROW_BACK:
		_on_back_pressed()
		return
	_select_card(_focused_row())


# The on-screen Back button and the Back row's confirm. One entry point, so the
# button and the pad/keyboard route can never drift apart.
func _on_back_pressed() -> void:
	SfxManager.play_ui_select()
	if menu_open:
		resume()


# Cycles through the focus rows: the move cards, the upgrade cards, the Back
# button. direction is +1 going down, -1 going up.
func _switch_active_column(direction : int = 1) -> void:
	var from_index : int = _focused_row()
	var to_index : int = wrapi(from_index + direction, 0, ROW_COUNT)
	if to_index == from_index:
		return
	SfxManager.play_ui_hover()
	p1_selection_column = to_index
	_refresh_row_focus()


# Puts the selector and the dimming on whichever row is focused now, and takes
# them off the one that no longer is. The card rows carry the card highlight;
# the Back row is a Button and carries focus itself.
func _refresh_row_focus() -> void:
	var active := _focused_row()
	for row in [ROW_UNLOCKS, ROW_UPGRADES]:
		var column := _get_column(row)
		if column == null:
			continue
		column.is_active = row == active
		_apply_focus_marker(column, column.focus_index, column.is_active)
		_layout_column(column, true)

	if back_button:
		if active == ROW_BACK:
			back_button.grab_focus()
		else:
			back_button.release_focus()


func _cycle_column(column : UpgradeColumn, direction : int) -> void:
	if column == null or column.cards.is_empty():
		return
	var last_index = column.cards.size() - 1
	var old_focus_index = column.focus_index
	column.focus_index = clampi(column.focus_index + direction, 0, last_index)
	if column.focus_index == old_focus_index:
		return

	SfxManager.play_ui_hover()
	_apply_focus_marker(column, old_focus_index, false)
	_apply_focus_marker(column, column.focus_index, true)
	_layout_column(column, true)


# Showing which card the selector is on is the card's own job - the same
# currently_highlighted + _handle_highlight() pair the mid-round draft drives
# (see card_hand.gd), which brings the blinking selector icon, its elastic pop
# and the springy scale-up with it. Doing it any other way here would be a
# second, subtly different definition of "selected".
func _apply_focus_marker(column : UpgradeColumn, index : int, highlighted : bool) -> void:
	if column == null or index < 0 or index >= column.cards.size():
		return
	# Typed as Variant deliberately: this is a duck-typed call onto whatever the
	# card scene's script provides, not a member of Node2D.
	var card : Variant = column.cards[index]
	if card == null:
		return
	card.currently_highlighted = highlighted
	card._handle_highlight()


func _focused_card_data(column : UpgradeColumn) -> UpgradeData:
	if column == null or column.cards.is_empty():
		return null
	if column.focus_index < 0 or column.focus_index >= column.cards.size():
		return null
	return column.upgrade_map.get(column.cards[column.focus_index])


func _get_column(column_index : int) -> UpgradeColumn:
	match column_index:
		ROW_UNLOCKS:
			return unlock
		ROW_UPGRADES:
			return upgrade
	return null


# -- Per-device input resolution --
# Same three helpers the other menus carry: a device answers through its own
# keys (keyboard) or its d-pad/buttons and stick (controller).

func _device_just_pressed(device: PlayerInputDevice, action_name: String) -> bool:
	if device == null:
		return false
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return _keyboard_action_just_pressed(action_name, device.native_action_suffix)
	if _joy_button_just_pressed(device.device_id, _joy_button_for_action(action_name)):
		return true
	return _joy_axis_just_pressed(device.device_id, action_name)


func _keyboard_action_just_pressed(base: String, suffix: String) -> bool:
	var just_pressed := false
	var keys : Array = GameManager.keyboard_layouts.get(suffix, {}).get(base, [])
	for event in keys:
		if not (event is InputEventKey):
			continue
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode
		var pressed : bool
		if code != KEY_NONE:
			pressed = Input.is_physical_key_pressed(code)
		else:
			code = key_event.keycode
			if code == KEY_NONE:
				continue
			pressed = Input.is_key_pressed(code)
		var was_pressed : bool = _key_prev_state.get(code, false)
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
		"Special":
			return JOY_BUTTON_B
		_:
			return JOY_BUTTON_A


func _joy_button_just_pressed(device_id: int, button_index: int) -> bool:
	var key := "%d_%d" % [device_id, button_index]
	var pressed := Input.is_joy_button_pressed(device_id, button_index)
	var was_pressed : bool = _joy_button_prev_state.get(key, false)
	_joy_button_prev_state[key] = pressed
	return pressed and not was_pressed


func _joy_axis_just_pressed(device_id: int, action_name: String) -> bool:
	var binding : Array = GameManager.JOY_AXIS_BASES.get(action_name, [])
	if binding.is_empty():
		return false
	var axis : int = binding[0]
	var direction : float = binding[1]
	var pressed := Input.get_joy_axis(device_id, axis) * direction >= GameManager.JOY_AXIS_DEADZONE
	var key := "%d_%d_%s" % [device_id, axis, direction]
	var was_pressed : bool = _joy_axis_prev_state.get(key, false)
	_joy_axis_prev_state[key] = pressed
	return pressed and not was_pressed


# --------------------------------------------------------------------------------------------------
# Displaying the equipped cards
#
# A horizontal row of everything picked so far, laid out around the anchor the
# tutorial background provides. Each entry is a real UpgradeCard, so it arrives
# with the same idle float every other card in the game has - there is no second
# animation system here.

func _draw_owned_cards() -> void:
	_clear_owned_cards()

	if equipped_cards_anchor == null or selected_cards.is_empty():
		return
	if card_default_scale == Vector2.ZERO:
		# The card scene has not been built yet (no upgrade arrays arrived), so
		# the scale to size the row against is not known.
		return

	var count := selected_cards.size()
	# Fit the row into the width the tutorial background gives it. A short
	# loadout stays at full size; a long one closes up and shrinks only as far
	# as it has to. The 0.92 leaves a visible gap between neighbours instead of
	# letting them touch.
	var spacing : float = minf(equipped_card_spacing, equipped_row_width / float(maxi(count, 1)))
	var width_per_card : float = maxf(card_art_width, 1.0)
	var fraction : float = minf(owned_card_scale_fraction, spacing * 0.92 / width_per_card)
	var row_scale : Vector2 = card_default_scale * fraction
	var first_x : float = -spacing * float(count - 1) * 0.5

	for i in count:
		var upgrade : UpgradeData = selected_cards[i]
		if upgrade == null:
			continue
		var offset := Vector2(first_x + spacing * float(i), 0.0)
		var owned_card := _spawn_owned_card(upgrade, offset, row_scale, i)
		if owned_card == null:
			continue
		await _reveal_owned_card(owned_card)
		if owned_card_flip_stagger_delay > 0.0:
			await get_tree().create_timer(owned_card_flip_stagger_delay).timeout


func _spawn_owned_card(upgrade: UpgradeData, offset: Vector2, target_scale: Vector2, index: int) -> Node2D:
	if equipped_cards_anchor == null:
		return null
	var owned_card := UPGRADE_CARD.instantiate() as Node2D
	if not owned_card:
		return null
	# Both of these have to be set before the card enters the tree: it starts its
	# idle float in _ready, and once the tree is running that float is already
	# under way with whatever phase it launched with.
	# is_display_only keeps this copy out of any hand's highlight/selection sweep.
	owned_card.is_display_only = true
	# Alternating cards start part-way up the float's cycle, so the row moves as
	# a row rather than in lockstep. Left at zero for every other card.
	if index % 2 == 1:
		owned_card.idle_bob_phase_offset = equipped_card_bob_phase

	equipped_cards_anchor.add_child(owned_card)
	owned_card.set_upgrade(upgrade)
	owned_card.z_index = owned_card_z_base + index * card_z_step

	owned_card.position = offset
	owned_card.scale = target_scale * spawn_scale_fraction

	var appear_tween = create_tween()
	appear_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	appear_tween.tween_property(owned_card, "scale", target_scale, owned_card_appear_duration)
	return owned_card


func _clear_owned_cards() -> void:
	if equipped_cards_anchor == null:
		return
	for card in equipped_cards_anchor.get_children():
		# Removed as well as freed: queue_free() only takes effect at the end of
		# the frame, so a redraw would otherwise show the old row and the new one
		# on top of each other for a frame.
		equipped_cards_anchor.remove_child(card)
		card.queue_free()


func _reveal_owned_card(owned_card: Node2D) -> void:
	if not is_instance_valid(owned_card):
		return
	owned_card.flip_card()
	# Waited out on a timer rather than on the card's own card_flip_finished
	# signal: picking again mid-reveal frees every card in the row, and a
	# coroutine awaiting a signal whose emitter has been freed never resumes.
	await get_tree().create_timer(_flip_seconds(owned_card)).timeout


# The flip animation's own length, so the reveal keeps in step with whatever
# upgrade_card.tscn's card_flip is actually timed at, falling back to the
# authored default if the card has no animation player or name to hand.
func _flip_seconds(owned_card: Node2D) -> float:
	if is_instance_valid(owned_card):
		var anim_player = owned_card.anim_player
		if anim_player and anim_player.has_animation(FLIP_ANIM):
			return anim_player.get_animation(FLIP_ANIM).length
	return fallback_flip_seconds
