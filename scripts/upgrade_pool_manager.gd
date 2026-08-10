extends Node

# NOTE currently is an active global script
const CARD_RESOURCE_DIR = "res://scripts/card_resource_files/"

var card_hand
#var rng = RandomNumberGenerator.new()
var card_array : Array[String] # Will hold the sum of all tres files in the card_resources_files
var draw_pile : Array[String] # This will hold the cards to be drawn in the card UI

var p1_upgrade_pool : Array[String]
var p2_upgrade_pool : Array[String]

var p1_current_upgrades : Array[String]
var p2_current_upgrades : Array[String]


func _ready() -> void:
	_get_files_from_dir()
	#_duplicate_card_pools() # NOTE Just here for testing purposes
	
# NOTE Call this function from the beginning of the match
func _duplicate_card_pools() -> void:
	p1_upgrade_pool.clear()
	p2_upgrade_pool.clear()
	
	p1_upgrade_pool = card_array.duplicate()
	print(p1_upgrade_pool)
	p2_upgrade_pool = card_array.duplicate()
	print(p2_upgrade_pool)


func _draw_from_pool(p1_lose : bool) -> Array[String]:
	# NOTE Duplication currently for all upgrade types
	var num_pool = _generate_unique_numbers()
	draw_pile.clear()
	if p1_lose == true:
		for i in range(0, card_hand.hand_limit):
			var card_to_add = p1_upgrade_pool.get(num_pool.pop_front())
			if card_to_add not in p1_current_upgrades:
				draw_pile.append(card_to_add)
			else:
				pass
		return draw_pile
	
	else:
		for i in range(0, card_hand.hand_limit):
			var card_to_add = p2_upgrade_pool.get(num_pool.pop_front())
			if card_to_add not in p2_current_upgrades:
				draw_pile.append(card_to_add)
			else:
				pass
		return draw_pile


func _get_files_from_dir() -> void:
	# Grabs all tres
	var dir = DirAccess.open(CARD_RESOURCE_DIR)
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var tres_file_path = CARD_RESOURCE_DIR + file_name
		card_array.append(tres_file_path)
		file_name = dir.get_next()


func _remove_from_pool(tres_path : String, p1_selection : bool) -> void:
	var upgrade_idx
	if p1_selection == true:
		upgrade_idx = p1_upgrade_pool.find(tres_path)
		p1_upgrade_pool.remove_at(upgrade_idx)
	else:
		upgrade_idx = p2_upgrade_pool.find(tres_path)
		p2_upgrade_pool.remove_at(upgrade_idx)


func _generate_unique_numbers() -> Array[int]:
	var num_pool = []
	for i in range(0, card_array.size()):
		num_pool.append(i)
	
	num_pool.shuffle()
	return num_pool.slice(0, card_hand.hand_limit)
	
