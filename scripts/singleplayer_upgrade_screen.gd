extends CanvasLayer

#@export var debug = true
var script_id = "SP Upgrade"

#@onready var player_current_cards_container = $MarginContainer/PanelContainer/MarginContainer/HBoxContainer/player_current_cards/current_cards_container
@onready var player_moves_node = $move_node
@onready var player_stats_node = $upgrade_node
@onready var active_cards_marker : Marker2D = $active_cards
@onready var owned_cards_spawn = $owned_cards_spawn

@export var base_card_scale_multiplier : float = 1.0 # cards read bigger here than in the mid round draft
@export var focused_extra_scale : float = 1.35 # extra growth on top of the base multiplier for the focused card
@export var scale_falloff_per_step : float = 0.28 # how much smaller each card gets per slot away from focus
@export var min_card_scale_fraction : float = 0.35
@export var alpha_falloff_per_step : float = 0.66 # how much more transparent each card gets per slot away from focus
@export var min_card_alpha : float = 0.01
@export var card_step_spacing : float = 92.0 # horizontal distance between adjacent card slots
@export var max_rendered_offset : int = 3 # cards further than this from focus are hidden outright
@export var card_move_duration : float = 0.18
@export var owned_card_reveal_start_delay : float = 0.01
@export var owned_card_z_base : int = 10
@export var card_z_step : int = 10
@export var owned_card_scale_fraction : float = 0.85
@export var owned_card_vertical_offset : float = 50.0
@export var spawn_scale_fraction : float = 0.05
@export var owned_card_appear_duration : float = 0.18
@export var owned_card_flip_stagger_delay : float = 0.0

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

var p1_selection_column : int = 0 # 0 for unlocks, 1 for upgrades
var default_z_index : int = 10
var menu_open : bool = false
var card_default_scale : Vector2
var selected_cards = []
var displayed_cards = []

class UpgradeColumn:
	var anchor : Node2D
	var wrappers : Array[CanvasGroup] = []
	var cards : Array[Node2D] = []
	var upgrade_map : Dictionary[Node2D, UpgradeData] = {}
	var focus_index : int = 0
	var locked : bool = false
	var locked_card : Node2D
	# The lock frame's blink tween, kept so unlocking can stop it. Without
	# this the frame keeps blinking after the column has been released.
	var lock_tween : Tween

var unlock : UpgradeColumn
var upgrade : UpgradeColumn

func _dbg(msg: String) -> void:
	if GameManager.debug:
		print_rich("[%s] %s" % [script_id, msg])


func _ready() -> void:
	if not GameManager.return_singleplayer_upgrade_arrays.is_connected(_on_recieve_arrays):
		GameManager.return_singleplayer_upgrade_arrays.connect(_on_recieve_arrays) # Connects to the signal that returns all the arrays with the upgrade data
	GameManager.request_singleplayer_upgrade_arrays.emit() # Emits the signal to request the arrays for the upgrade data
	self.hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_test_toggle_menu()
	
	if not menu_open:
		return
		
	_handle_player_input(1)


func _test_toggle_menu() -> void:
	if Input.is_action_just_pressed("UpgradeMenuToggle"):
		if menu_open:
			resume()
		else:
			pause()


func resume():
	GameManager.player_input_locked = false
	hide()
	menu_open = false
	_apply_selected_upgrades()

func pause():
	show()
	GameManager.player_input_locked = true
	menu_open = true
	# TODO: Reset the player stats here


func _select_card(column_index : int) -> void:
	var column = _get_column(column_index)
	var selected_card = column.cards[column.focus_index]
	
	selected_cards.append(column.upgrade_map.get(selected_card))
	
	_dbg("[SELECT CARD] Current card array: %s" % [selected_cards])


func _apply_selected_upgrades() -> void:
	for upgrade in selected_cards:
		_dbg("[UPGRADE APPLICATION] Applied upgrade: %s" % upgrade)
		upgrade.apply_to(GameManager.p1_node)


# --------------------------------------------------------------------------------------------------
# Handling building the columns and card tweens

func _build_column(anchor : Node2D, upgrades : Array[UpgradeData]) -> UpgradeColumn:
	var column := UpgradeColumn.new()
	column.anchor = anchor

	for upgrade in upgrades:
		var card = UPGRADE_CARD.instantiate()
		var wrapper := CanvasGroup.new()
		wrapper.add_child(card)

		anchor.add_child(wrapper)
		anchor.move_child(wrapper, 0) # keep lock_frame drawing on top of the cards
		card.set_upgrade(upgrade)
		card.flip_card()
		card.show()

		column.wrappers.append(wrapper)
		column.cards.append(card)
		column.upgrade_map.set(card, upgrade)

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
		var target_scale = _card_scale_for_offset(offset)
		var target_alpha = _card_alpha_for_offset(offset)

		if animate:
			_tween_card(wrapper, target_position, target_scale, target_alpha)
		else:
			wrapper.position = target_position
			wrapper.scale = target_scale
			wrapper.modulate.a = target_alpha


func _card_scale_for_offset(offset : int) -> Vector2:
	var step_penalty = scale_falloff_per_step * absi(offset)
	var extra = focused_extra_scale if offset == 0 else 1.0
	var scale_fraction = maxf(min_card_scale_fraction, extra - step_penalty)
	return Vector2.ONE * base_card_scale_multiplier * scale_fraction
	

func _card_alpha_for_offset(offset : int) -> float:
	return maxf(min_card_alpha, 1.0 - alpha_falloff_per_step * absi(offset))
	

func _tween_card(wrapper : CanvasGroup, target_position : Vector2, target_scale : Vector2, target_alpha : float) -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(wrapper, "position", target_position, card_move_duration)
	tween.tween_property(wrapper, "scale", target_scale, card_move_duration)
	tween.tween_property(wrapper, "modulate:a", target_alpha, card_move_duration)


func _on_recieve_arrays(move_array : Array[UpgradeData], upgrade_array : Array[UpgradeData]) -> void:
	unlock = _build_column(player_moves_node, move_array)
	upgrade = _build_column(player_stats_node, upgrade_array)
	
	_layout_column(unlock, false)
	_layout_column(upgrade, false)


# --------------------------------------------------------------------------------------------------
# Player input handling in the menu

func _handle_player_input(player_id : int) -> void:
	var suffix = "P%d" % player_id
	var column_index = _get_selection_column()
	var column = _get_column(column_index)

	if Input.is_action_just_pressed("Up" + suffix) or Input.is_action_just_pressed("Down" + suffix):
		_switch_active_column()
	elif Input.is_action_just_pressed("Special" + suffix):
		# Back out of a card that's already locked in, so a mis-pick can be
		# redone instead of stranding the player with it.
		#_unlock_column(player_id, column_index)
		pass
	elif Input.is_action_just_pressed("Left" + suffix):
		if column.locked:
			return
		_cycle_column(column, -1)
	elif Input.is_action_just_pressed("Right" + suffix):
		if column.locked:
			return
		_cycle_column(column, 1)
	elif Input.is_action_just_pressed("Normal" + suffix):
		_select_card(column_index)
		_draw_owned_cards(1)
		pass


func _get_selection_column() -> int:
	return p1_selection_column


func _get_column(column_index : int) -> UpgradeColumn:
	return unlock if column_index == 0 else upgrade


func _set_selection_column(value : int) -> void:
	p1_selection_column = value


func _switch_active_column() -> void:
	var from_index = _get_selection_column()
	var to_index = 1 - from_index
	var from_column = _get_column(from_index)
	var to_column = _get_column(to_index)

	SfxManager.play_ui_hover()
	from_column.cards[from_column.focus_index].selection_icon.hide()
	to_column.cards[to_column.focus_index].selection_icon.show()
	_set_selection_column(to_index)


func _cycle_column(column : UpgradeColumn, direction : int) -> void:
	var last_index = column.wrappers.size() - 1
	var old_focus_index = column.focus_index
	column.focus_index = clampi(column.focus_index + direction, 0, last_index)
	if column.focus_index == old_focus_index:
		return

	SfxManager.play_ui_hover()
	column.cards[old_focus_index].selection_icon.hide()
	column.cards[column.focus_index].selection_icon.show()
	_layout_column(column, true)


# --------------------------------------------------------------------------------------------------
# Displaying the upgrade in the menu

func _spawn_owned_card(upgrade: UpgradeData, index: int) -> Node2D:
	var owned_card := UPGRADE_CARD.instantiate() as Node2D
	if not owned_card:
		return null
	# Keeps this copy out of the hand's highlight/selection sweep.
	owned_card.is_display_only = true
	owned_cards_spawn.add_child(owned_card)
	owned_card.set_upgrade(upgrade)
	owned_card.z_index = owned_card_z_base + index * card_z_step

	var base_scale = card_default_scale #if defaults_set else owned_card.scale
	var target_scale = base_scale * owned_card_scale_fraction
	owned_card.rotation = 0.0
	owned_card.position = active_cards_marker.position + Vector2(0, index * owned_card_vertical_offset)
	owned_card.scale = target_scale * spawn_scale_fraction

	var appear_tween = create_tween()
	appear_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	appear_tween.tween_property(owned_card, "scale", target_scale, owned_card_appear_duration)

	displayed_cards.append(owned_card)
	return owned_card


func _draw_owned_cards(player_id: int) -> void:
	_clear_owned_cards()

	var picked: Array = selected_cards
	if picked.is_empty():
		return

	# Let the scene transition's wipe clear first, otherwise the whole
	# reveal plays out behind a closed mouth and is never actually seen.
	if owned_card_reveal_start_delay > 0.0:
		await get_tree().create_timer(owned_card_reveal_start_delay).timeout

	var index := 0
	for upgrade in picked:
		if upgrade == null:
			continue

		var owned_card := _spawn_owned_card(upgrade, index)
		index += 1
		if owned_card == null:
			continue
		await _reveal_owned_card(owned_card)

		if owned_card_flip_stagger_delay > 0.0:
			await get_tree().create_timer(owned_card_flip_stagger_delay).timeout


func _clear_owned_cards() -> void:
	for card in displayed_cards:
		if is_instance_valid(card):
			card.queue_free()
	displayed_cards.clear()


func _reveal_owned_card(owned_card: Node2D) -> void:
	if not is_instance_valid(owned_card):
		return
	if owned_card_appear_duration > 0.0:
		await get_tree().create_timer(owned_card_appear_duration).timeout
	if not is_instance_valid(owned_card):
		return
	owned_card.flip_card()
	await owned_card.card_flip_finished
