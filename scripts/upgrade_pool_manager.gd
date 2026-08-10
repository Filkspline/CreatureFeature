extends Node

# NOTE currently is an active global script
const CARD_RESOURCE_DIR = "res://scripts/card_resource_files/"

var card_hand
var card_array : Array[String] ## Will hold the sum of all tres files in the card_resources_files
var draw_pile : Array[String] ## This will hold the cards to be drawn in the card UI

var p1_upgrade_pool : Array[String]
var p2_upgrade_pool : Array[String]

var p1_current_upgrades : Array[String]
var p2_current_upgrades : Array[String]


func _ready() -> void:
	_get_files_from_dir()
	#_duplicate_card_pools() # NOTE Just here for testing purposes
	

## Duplicates the card pools from the global card array that contains all cards.
## Additionally clears both p1, and p2 upgrade pools beforehand as a precaution.
func _duplicate_card_pools() -> void:
	# NOTE Call this function from the beginning of the match
	p1_upgrade_pool.clear()
	p2_upgrade_pool.clear()
	
	p1_upgrade_pool = card_array.duplicate()
	#print(p1_upgrade_pool)
	p2_upgrade_pool = card_array.duplicate()
	#print(p2_upgrade_pool)


## Facilitates the card draw from the global card pool for the given player.
## Currently a bool which denotes which player is currently selecting, true for
## p1 selecting, false for p2 selecting
func _draw_from_pool(p1_lose : bool) -> Array[String]:
	# NOTE Duplication currently for all upgrade types
	
	# TODO When we implement move unlocks we will need to make adjustments to
	# this function, we'll need to uncomment the if statements as well as
	# implement a check for unlock cards to stop them from being added
	# ALternattively we just nuke them from the upgrade pool when they've been
	# added.
	var num_pool = _generate_unique_numbers()
	draw_pile.clear()
	if p1_lose == true:
		for i in range(0, card_hand.hand_limit):
			var card_to_add = p1_upgrade_pool.get(num_pool.pop_front())
			#if card_to_add not in p1_current_upgrades:
			draw_pile.append(card_to_add)
			#else:
			#	pass
		return draw_pile
	
	else:
		for i in range(0, card_hand.hand_limit):
			var card_to_add = p2_upgrade_pool.get(num_pool.pop_front())
			#if card_to_add not in p2_current_upgrades:
			draw_pile.append(card_to_add)
			#else:
			#	pass
		return draw_pile


## Grabs all tres files from the card_resource_files folder.
## Currently does not parse file type just grabbing all files in the folder
func _get_files_from_dir() -> void:
	var dir = DirAccess.open(CARD_RESOURCE_DIR)
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var tres_file_path = CARD_RESOURCE_DIR + file_name
		card_array.append(tres_file_path)
		file_name = dir.get_next()


## Removes the passed resource file in the player upgrade pools, passing in
## a bool which denotes which player is currently selecting, true for p1
## selecting, false for p2 selecting
func _remove_from_pool(tres_path : String, p1_selection : bool) -> void:
	
	var upgrade_idx
	if p1_selection == true:
		upgrade_idx = p1_upgrade_pool.find(tres_path)
		p1_upgrade_pool.remove_at(upgrade_idx)
	else:
		upgrade_idx = p2_upgrade_pool.find(tres_path)
		p2_upgrade_pool.remove_at(upgrade_idx)


## Generates an array of unique numbers to be used as the index for the card
## draw system in _draw_from_pool
func _generate_unique_numbers() -> Array[int]:
	var num_pool = []
	for i in range(0, card_array.size()):
		num_pool.append(i)
	
	num_pool.shuffle()
	return num_pool.slice(0, card_hand.hand_limit)
	
