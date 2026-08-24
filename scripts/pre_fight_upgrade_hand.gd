extends Node2D

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

@export_category("Player info")
@export_enum("Player 1:1", "Player 2:2") var player_id : int

#@export var folder_node_path : NodePath = ^"../../taskbar/folder" # The folder sprite that bulges each time a card pops out

@onready var p1_card_spawner : Marker2D = $"../taskbar/p1_folder/p1_card_spawn"
@onready var p2_card_spawner : Marker2D = $"../taskbar/p2_folder/p2_card_spawn"
#@onready var folder_sprite : Sprite2D = get_node(folder_node_path)

# Yes these are all globals, I cannot be bothered to actually pass every single array into a function
# each time I need to do that
var unlock_array : Array[UpgradeData] = []
var stat_upgrade_array : Array[UpgradeData] = []

var p1_unlock_map : Dictionary[Node2D, UpgradeData]
var p1_upgrade_map : Dictionary[Node2D, UpgradeData]
var p2_unlock_map : Dictionary[Node2D, UpgradeData]
var p2_upgrade_map : Dictionary[Node2D, UpgradeData]

func _ready() -> void:
	GameManager.return_first_upgrade_arrays.connect(_on_arrays_recieved) # Connects to the signal that returns all the arrays with the upgrade data
	GameManager.request_first_upgrade_arrays.emit() # Emits the signal to request the arrays for the upgrade data


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_arrays_recieved(move_array : Array[UpgradeData], upgrade_array : Array[UpgradeData]) -> void:
	#print_rich("[color=green][PRE-FIGHT] Arrays recieved")
	unlock_array = move_array
	stat_upgrade_array = upgrade_array
	_draw_hands()

func _draw_hands() -> void:
	#print_rich("[color=green][PRE-FIGHT] Draw hands starting")
	#print_rich("[color=yellow][PRE-FIGHT] Unlock array: (%s), Upgrade array: (%s)" % [unlock_array, stat_upgrade_array])
	for unlock in unlock_array:
		#print_rich("[color=yellow][PRE-FIGHT] Unlock loop")
		var p1_unlock_card = UPGRADE_CARD.instantiate()
		var p2_unlock_card = UPGRADE_CARD.instantiate()
		p1_unlock_map.set(p1_unlock_card, unlock)
		p2_unlock_map.set(p2_unlock_card, unlock)
		
		#if player_id == 1:
		#	print("Test1")
		#	self.add_child(p1_unlock_card)
		#	p1_unlock_card.set_upgrade(unlock)
		#if player_id == 2:
		#	print("Test2")
		#	self.add_child(p2_unlock_card)
		#	p2_unlock_card.set_upgrade(unlock)
		
		match player_id:
			1:
				#print_rich("[color=yellow][PRE-FIGHT] Match P1 doing unlock_cards")
				self.add_child(p1_unlock_card)
				p1_unlock_card.set_upgrade(unlock)
			2:
				#print_rich("[color=yellow][PRE-FIGHT] Match P2 doing unlock_cards")
				self.add_child(p2_unlock_card)
				p2_unlock_card.set_upgrade(unlock)
		
	for upgrade in stat_upgrade_array:
		#print_rich("[color=yellow][PRE-FIGHT] Upgrade loop")
		var p1_stat_card = UPGRADE_CARD.instantiate()
		var p2_stat_card = UPGRADE_CARD.instantiate()
		p1_upgrade_map.set(p1_stat_card, upgrade)
		p2_upgrade_map.set(p2_stat_card, upgrade)
		
		match player_id:
			1:
				#print_rich("[color=yellow][PRE-FIGHT] Match P1 doing upgrade_cards")
				self.add_child(p1_stat_card)
				p1_stat_card.set_upgrade(upgrade)
			2:
				#print_rich("[color=yellow][PRE-FIGHT] Match P2 doing upgrade_cards")
				self.add_child(p2_stat_card)
				p2_stat_card.set_upgrade(upgrade)
			
	
	print_rich("[PRE FIGHT] P1 unlock map: %s, map size: %s" % [p1_unlock_map, p1_unlock_map.size()])
	print_rich("[PRE FIGHT] P1 upgrade map: %s, map size: %s\n" % [p1_upgrade_map, p1_upgrade_map.size()])
	print_rich("[PRE FIGHT] P2 unlock map: %s, map size: %s" % [p2_unlock_map, p2_unlock_map.size()])
	print_rich("[PRE FIGHT] P2 upgrade map: %s, map size: %s\n" % [p2_upgrade_map, p2_upgrade_map.size()])
