extends Node2D

#  PreFightUpgradeHand (boot screen draft UI)
#

const FIGHT_SCENE = "res://scenes/test_level.tscn"
const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

const TOTAL_COLUMNS_PER_PLAYER := 2 # unlock + upgrade
const LOCK_BLINK_INTERVAL := 0.4 # matches a DOS-style blinking cursor
const LOADING_FILL_DURATION := 0.35

const P1_ACCENT_COLOR := Color(1.0, 1.0, 1.0) # white
const P2_ACCENT_COLOR := Color(0.79607844, 0.85882354, 0.9882353) # cbdbfc

@export var base_card_scale_multiplier : float = 1.0 # cards read bigger here than in the mid round draft
@export var focused_extra_scale : float = 1.35 # extra growth on top of the base multiplier for the focused card
@export var scale_falloff_per_step : float = 0.28 # how much smaller each card gets per slot away from focus
@export var min_card_scale_fraction : float = 0.35
@export var alpha_falloff_per_step : float = 0.66 # how much more transparent each card gets per slot away from focus
@export var min_card_alpha : float = 0.15
@export var card_step_spacing : float = 92.0 # horizontal distance between adjacent card slots
@export var max_rendered_offset : int = 3 # cards further than this from focus are hidden outright
@export var card_move_duration : float = 0.18


class UpgradeColumn:
	var anchor : Node2D
	var wrappers : Array[CanvasGroup] = []
	var cards : Array[Node2D] = []
	var upgrade_map : Dictionary[Node2D, UpgradeData] = {}
	var focus_index : int = 0
	var locked : bool = false
	var locked_card : Node2D


@onready var p1_hand_unlock : Node2D = $p1_hand_unlock
@onready var p1_hand_upgrade : Node2D = $p1_hand_upgrade
@onready var p2_hand_unlock : Node2D = $p2_hand_unlock
@onready var p2_hand_upgrade : Node2D = $p2_hand_upgrade

@onready var p1_loading_track : Control = $p1_panel/p1_loading_track
@onready var p1_loading_fill : Control = $p1_panel/p1_loading_track/p1_loading_fill
@onready var p2_loading_track : Control = $p2_panel/p2_loading_track
@onready var p2_loading_fill : Control = $p2_panel/p2_loading_track/p2_loading_fill

@onready var p1_ready_label : Label = $p1_panel/p1_ready_label
@onready var p2_ready_label : Label = $p2_panel/p2_ready_label

@onready var p1_unlock_lock_frame : Control = $p1_hand_unlock/lock_frame
@onready var p1_upgrade_lock_frame : Control = $p1_hand_upgrade/lock_frame
@onready var p2_unlock_lock_frame : Control = $p2_hand_unlock/lock_frame
@onready var p2_upgrade_lock_frame : Control = $p2_hand_upgrade/lock_frame

# Yes these are all globals, I cannot be bothered to actually pass every single array into a function
# each time I need to do that
var unlock_array : Array[UpgradeData] = []
var stat_upgrade_array : Array[UpgradeData] = []

var p1_unlock : UpgradeColumn
var p1_upgrade : UpgradeColumn
var p2_unlock : UpgradeColumn
var p2_upgrade : UpgradeColumn

var p1_selection_column : int = 0 # 0 for unlocks, 1 for upgrades
var p2_selection_column : int = 0


func _ready() -> void:
	if not GameManager.request_first_upgrade_arrays.is_connected(_on_arrays_recieved):
		GameManager.return_first_upgrade_arrays.connect(_on_arrays_recieved) # Connects to the signal that returns all the arrays with the upgrade data
	GameManager.request_first_upgrade_arrays.emit() # Emits the signal to request the arrays for the upgrade data


func _process(_delta: float) -> void:
	_handle_player_input(1)
	_handle_player_input(2)


func _on_arrays_recieved(move_array : Array[UpgradeData], upgrade_array : Array[UpgradeData]) -> void:
	unlock_array = move_array
	stat_upgrade_array = upgrade_array
	_draw_hands()


func _draw_hands() -> void:
	p1_unlock = _build_column(p1_hand_unlock, unlock_array)
	p1_upgrade = _build_column(p1_hand_upgrade, stat_upgrade_array)
	p2_unlock = _build_column(p2_hand_unlock, unlock_array)
	p2_upgrade = _build_column(p2_hand_upgrade, stat_upgrade_array)

	_layout_column(p1_unlock, false)
	_layout_column(p1_upgrade, false)
	_layout_column(p2_unlock, false)
	_layout_column(p2_upgrade, false)

	p1_unlock.cards[0].selection_icon.show()
	p2_unlock.cards[0].selection_icon.show()


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


func _get_column(player_id : int, column_index : int) -> UpgradeColumn:
	if player_id == 1:
		return p1_unlock if column_index == 0 else p1_upgrade
	return p2_unlock if column_index == 0 else p2_upgrade


func _get_selection_column(player_id : int) -> int:
	return p1_selection_column if player_id == 1 else p2_selection_column


func _set_selection_column(player_id : int, value : int) -> void:
	if player_id == 1:
		p1_selection_column = value
	else:
		p2_selection_column = value


func _get_lock_frame(player_id : int, column_index : int) -> Control:
	if player_id == 1:
		return p1_unlock_lock_frame if column_index == 0 else p1_upgrade_lock_frame
	return p2_unlock_lock_frame if column_index == 0 else p2_upgrade_lock_frame


func _cycle_column(column : UpgradeColumn, direction : int) -> void:
	var last_index = column.wrappers.size() - 1
	var old_focus_index = column.focus_index
	column.focus_index = clampi(column.focus_index + direction, 0, last_index)
	if column.focus_index == old_focus_index:
		return

	column.cards[old_focus_index].selection_icon.hide()
	column.cards[column.focus_index].selection_icon.show()
	_layout_column(column, true)


func _switch_active_column(player_id : int) -> void:
	var from_index = _get_selection_column(player_id)
	var to_index = 1 - from_index
	var from_column = _get_column(player_id, from_index)
	var to_column = _get_column(player_id, to_index)

	from_column.cards[from_column.focus_index].selection_icon.hide()
	to_column.cards[to_column.focus_index].selection_icon.show()
	_set_selection_column(player_id, to_index)


func _handle_player_input(player_id : int) -> void:
	var suffix = "P%d" % player_id
	var column_index = _get_selection_column(player_id)
	var column = _get_column(player_id, column_index)

	if Input.is_action_just_pressed("Up" + suffix) or Input.is_action_just_pressed("Down" + suffix):
		_switch_active_column(player_id)
	elif Input.is_action_just_pressed("Left" + suffix):
		if column.locked:
			return
		_cycle_column(column, -1)
	elif Input.is_action_just_pressed("Right" + suffix):
		if column.locked:
			return
		_cycle_column(column, 1)
	elif Input.is_action_just_pressed("Normal" + suffix):
		_select_card(player_id, column_index)


func _select_card(player_id : int, column_index : int) -> void:
	var column = _get_column(player_id, column_index)
	if column.locked:
		return

	column.locked = true
	column.locked_card = column.cards[column.focus_index]
	_show_lock_feedback(player_id, column_index)
	_advance_loading_bar(player_id)
	_check_selection_status()


func _show_lock_feedback(player_id : int, column_index : int) -> void:
	# Blinks the lock frame like a DOS cursor, unmistakable at a glance
	# that this column is locked in and can't be cycled anymore.
	var frame = _get_lock_frame(player_id, column_index)
	frame.show()

	var tween = create_tween()
	tween.set_loops()
	tween.tween_interval(LOCK_BLINK_INTERVAL)
	tween.tween_callback(frame.hide)
	tween.tween_interval(LOCK_BLINK_INTERVAL)
	tween.tween_callback(frame.show)


func _advance_loading_bar(player_id : int) -> void:
	var locked_count = _locked_column_count(player_id)
	var fraction = float(locked_count) / float(TOTAL_COLUMNS_PER_PLAYER)
	var track = p1_loading_track if player_id == 1 else p2_loading_track
	var fill = p1_loading_fill if player_id == 1 else p2_loading_fill

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fill, "size:x", track.size.x * fraction, LOADING_FILL_DURATION)

	if locked_count == TOTAL_COLUMNS_PER_PLAYER:
		_show_ready_label(player_id)


func _locked_column_count(player_id : int) -> int:
	var count = 0
	if _get_column(player_id, 0).locked:
		count += 1
	if _get_column(player_id, 1).locked:
		count += 1
	return count


func _show_ready_label(player_id : int) -> void:
	var label = p1_ready_label if player_id == 1 else p2_ready_label
	label.modulate.a = 0.0
	label.show()

	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)


func _check_selection_status() -> void:
	print_rich("[color=yellow][PRE FIGHT] P1 Unl: %s, P1 Upg: %s, P2 Unl: %s, P2 Upg: %s" % [p1_unlock.locked, p1_upgrade.locked, p2_unlock.locked, p2_upgrade.locked])

	if p1_unlock.locked and p1_upgrade.locked and p2_unlock.locked and p2_upgrade.locked:
		_send_off_upgrades()
		SceneTransition.change_scene(FIGHT_SCENE)


func _send_off_upgrades() -> void:
	EventBus.upgrade_picked.emit(1, p1_unlock.upgrade_map.get(p1_unlock.locked_card))
	EventBus.upgrade_picked.emit(1, p1_upgrade.upgrade_map.get(p1_upgrade.locked_card))
	EventBus.upgrade_picked.emit(2, p2_unlock.upgrade_map.get(p2_unlock.locked_card))
	EventBus.upgrade_picked.emit(2, p2_upgrade.upgrade_map.get(p2_upgrade.locked_card))
