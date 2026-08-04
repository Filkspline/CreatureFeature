extends Node

# NOTE currently is an active global script
const CARD_RESOURCE_DIR = "res://scripts/card_resource_files/"

var card_hand
var rng = RandomNumberGenerator.new()
# NOTE This should contain the tres file names for the cards
# NOTE we may need to do this manually
var card_array : Array[String] = ["res://scripts/card_resource_files/test_card_1.tres", "res://scripts/card_resource_files/test_card_2.tres", "res://scripts/card_resource_files/test_card_3.tres", "res://scripts/card_resource_files/test_card_4.tres", "res://scripts/card_resource_files/test_card_5.tres"] 
var draw_pile : Array[String] = []

# NOTE Node2D would read ALL info from a card tres file, change to handle that

func _draw_from_dict() -> Array[String]:
	for i in range(0, card_hand.hand_limit):
		var random_num = rng.randf_range(0, card_hand.hand_limit - 1)
		draw_pile.append(card_array.get(random_num))
	return draw_pile


#func _get_tres_file_and_apply(file_to_get : String) -> void:
	# TODO whatever the fuck is needed here to deal with .tres files, that shit is magic to me
#	pass
