extends Node

# NOTE currently is an active global script
const CARD_RESOURCE_DIR = "res://scripts/card_resource_files/"

var card_hand
var rng = RandomNumberGenerator.new()
var card_array : Array[String] = [] # Will hold the sum of all tres files in the card_resources_files
var draw_pile : Array[String] = [] # This will hold the cards to be drawn in the card UI

func _ready() -> void:
	_get_files_from_dir()


func _draw_from_dict() -> Array[String]:
	for i in range(0, card_hand.hand_limit):
		var random_num = rng.randf_range(0, card_hand.hand_limit - 1)
		draw_pile.append(card_array.get(random_num))
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
