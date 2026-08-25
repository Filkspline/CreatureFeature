extends Node2D

const FIGHT_SCENE = "res://scenes/test_level.tscn"
const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

@onready var p1_card_spawner : Marker2D = $taskbar/p1_folder/p1_card_spawn
@onready var p2_card_spawner : Marker2D = $taskbar/p2_folder/p2_card_spawn
@onready var p1_hand_unlock : Node2D = $p1_hand_unlock
@onready var p1_hand_upgrade : Node2D = $p1_hand_upgrade
@onready var p2_hand_unlock : Node2D = $p2_hand_unlock
@onready var p2_hand_upgrade : Node2D = $p2_hand_upgrade

# Yes these are all globals, I cannot be bothered to actually pass every single array into a function
# each time I need to do that
var unlock_array : Array[UpgradeData] = []
var stat_upgrade_array : Array[UpgradeData] = []

var p1_unlock_map : Dictionary[Node2D, UpgradeData]
var p1_upgrade_map : Dictionary[Node2D, UpgradeData]
var p2_unlock_map : Dictionary[Node2D, UpgradeData]
var p2_upgrade_map : Dictionary[Node2D, UpgradeData]

var p1_selections : Array[Array] = [[], []] # Nested arrays to handle the two columns for which upgrade is selected
var p2_selections : Array[Array] = [[], []]

var p1_selection_column : int = 0 # 0 for unlocks, 1 for upgrades
var p2_selection_column : int = 0

var p1_unlock_selected : bool = false
var p1_upgrade_selected : bool = false
var p2_unlock_selected : bool = false
var p2_upgrade_selected: bool = false

var p1_selected_unlock : Node2D
var p1_selected_upgrade : Node2D
var p2_selected_unlock : Node2D
var P2_selected_upgrade : Node2D


func _ready() -> void:
	if not GameManager.request_first_upgrade_arrays.is_connected(_on_arrays_recieved):
		GameManager.return_first_upgrade_arrays.connect(_on_arrays_recieved) # Connects to the signal that returns all the arrays with the upgrade data
	GameManager.request_first_upgrade_arrays.emit() # Emits the signal to request the arrays for the upgrade data


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_handle_p1_input()
	_handle_p2_input()


func _on_arrays_recieved(move_array : Array[UpgradeData], upgrade_array : Array[UpgradeData]) -> void:
	unlock_array = move_array
	stat_upgrade_array = upgrade_array
	_draw_hands()


func _draw_hands() -> void:
	for unlock in unlock_array:
		var p1_unlock_card = UPGRADE_CARD.instantiate()
		var p2_unlock_card = UPGRADE_CARD.instantiate()
		p1_unlock_map.set(p1_unlock_card, unlock)
		p2_unlock_map.set(p2_unlock_card, unlock)
	
		p1_hand_unlock.add_child(p1_unlock_card)
		p1_unlock_card.set_upgrade(unlock)
		p1_selections[0].append(p1_unlock_card)
		p1_unlock_card.hide()
			
		p2_hand_unlock.add_child(p2_unlock_card)
		p2_unlock_card.set_upgrade(unlock)
		p2_selections[0].append(p2_unlock_card)
		p2_unlock_card.hide()
		
		p1_unlock_card.flip_card()
		p2_unlock_card.flip_card()
		
	for upgrade in stat_upgrade_array:
		var p1_stat_card = UPGRADE_CARD.instantiate()
		var p2_stat_card = UPGRADE_CARD.instantiate()
		p1_upgrade_map.set(p1_stat_card, upgrade)
		p2_upgrade_map.set(p2_stat_card, upgrade)
		
		p1_hand_upgrade.add_child(p1_stat_card)
		p1_stat_card.set_upgrade(upgrade)
		p1_selections[1].append(p1_stat_card)
		p1_stat_card.hide()
			
		p2_hand_upgrade.add_child(p2_stat_card)
		p2_stat_card.set_upgrade(upgrade)
		p2_selections[1].append(p2_stat_card)
		p2_stat_card.hide()
		
		p1_stat_card.flip_card()
		p2_stat_card.flip_card()
	
	p1_selections[0][0].show()
	p1_selections[1][0].show()
	p2_selections[0][0].show()
	p2_selections[1][0].show()
	
	p1_selections[0][0].selection_icon.show()
	p2_selections[0][0].selection_icon.show()


func _cycle_up(column : int, selection_array : Array[Array]) -> void:
	var node_to_append : Node2D
	node_to_append = selection_array[column].pop_front()
	node_to_append.hide()
	node_to_append.selection_icon.hide()
	selection_array[column][0].show()
	selection_array[column][0].selection_icon.show()
	selection_array[column].push_back(node_to_append)


func _cycle_down(column : int, selection_array : Array[Array]) -> void:
	var node_to_append : Node2D
	node_to_append = selection_array[column].pop_back()
	selection_array[column][0].hide()
	selection_array[column][0].selection_icon.hide()
	selection_array[column].push_front(node_to_append)
	selection_array[column][0].show()
	selection_array[column][0].selection_icon.show()


func _select_card(column : int, player_id : int) -> void:
	if column == 0 and player_id == 1:
		p1_unlock_selected = true
		p1_selected_unlock = p1_selections[column][0]
	elif column == 1 and player_id == 1:
		p1_upgrade_selected = true
		p1_selected_upgrade = p1_selections[column][0]
	elif column == 0 and player_id == 2:
		p2_unlock_selected = true
		p2_selected_unlock = p2_selections[column][0]
	elif column == 1 and player_id == 2:
		p2_upgrade_selected = true
		P2_selected_upgrade = p2_selections[column][0]
		
	_check_selection_status()


func _handle_p1_input() -> void:
	if Input.is_action_just_pressed("LeftP1") or Input.is_action_just_pressed("RightP1"):
		if p1_selection_column == 0:
			p1_selection_column = 1
			p1_selections[0][0].selection_icon.hide()
			p1_selections[1][0].selection_icon.show()
		elif p1_selection_column == 1:
			p1_selection_column = 0
			p1_selections[1][0].selection_icon.hide()
			p1_selections[0][0].selection_icon.show()
	elif Input.is_action_just_pressed("UpP1"):
		if _check_for_lock(p1_selection_column, 1):
			_cycle_up(p1_selection_column, p1_selections)
	elif Input.is_action_just_pressed("DownP1"):
		if _check_for_lock(p1_selection_column, 1):
			_cycle_down(p1_selection_column, p1_selections)
	elif Input.is_action_just_pressed("NormalP1"):
		_select_card(p1_selection_column, 1)


func _handle_p2_input() -> void:
	if Input.is_action_just_pressed("LeftP2") or Input.is_action_just_pressed("RightP2"):
		if p2_selection_column == 0:
			p2_selection_column = 1
			p2_selections[0][0].selection_icon.hide()
			p2_selections[1][0].selection_icon.show()
		elif p2_selection_column == 1:
			p2_selection_column = 0
			p2_selections[1][0].selection_icon.hide()
			p2_selections[0][0].selection_icon.show()
	elif Input.is_action_just_pressed("UpP2"):
		if _check_for_lock(p2_selection_column, 2):
			_cycle_up(p2_selection_column, p2_selections)
	elif Input.is_action_just_pressed("DownP2"):
		if _check_for_lock(p2_selection_column, 2):
			_cycle_down(p2_selection_column, p2_selections)
	elif Input.is_action_just_pressed("NormalP2"):
		_select_card(p2_selection_column, 2)


func _check_for_lock(column : int, player_id : int) -> bool:
	if column == 0 and player_id == 1 and p1_unlock_selected == true:
		return false
	elif column == 1 and player_id == 1 and p1_upgrade_selected == true:
		return false
	elif column == 0 and player_id == 2 and p2_unlock_selected == true:
		return false
	elif column == 1 and player_id == 2 and p2_upgrade_selected == true:
		return false
	else:
		return true


func _check_selection_status() -> void:
	print_rich("[color=yellow][PRE FIGHT] P1 Unl Selected: %s, P1 Upg Selected: %s, P2 Unl Selected: %s, P2 Upg Selected: %s" % [p1_unlock_selected, p1_upgrade_selected, p2_unlock_selected, p2_upgrade_selected])
	
	if p1_unlock_selected and p1_upgrade_selected and p2_unlock_selected and p2_upgrade_selected:
		_send_off_upgrades()
		SceneTransition.change_scene(FIGHT_SCENE)


func _send_off_upgrades() -> void:
	var p1_unlock_data = p1_unlock_map.get(p1_selected_unlock)
	EventBus.upgrade_picked.emit(1, p1_unlock_data)
	var p1_upgrade_data = p1_upgrade_map.get(p1_selected_upgrade)
	EventBus.upgrade_picked.emit(1, p1_upgrade_data)
	var p2_unlock_data = p2_unlock_map.get(p2_selected_unlock)
	EventBus.upgrade_picked.emit(2, p2_unlock_data)
	var p2_upgrade_data = p2_upgrade_map.get(P2_selected_upgrade)
	EventBus.upgrade_picked.emit(2, p2_upgrade_data)
	
	
