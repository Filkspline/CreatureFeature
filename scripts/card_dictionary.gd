extends Node

# NOTE currently is an active global script

var card_hand
var rng = RandomNumberGenerator.new()
var card_dictionary : Dictionary = {}
var card_array : Array[Node2D] = [] # NOTE This should contain the Node2D's for the cards from the boot up of the game
var draw_pile : Array[Node2D] = []

func _draw_from_dict() -> Array[Node2D]:
	for i in range(1, card_hand.hand_limit):
		var random_num = rng.randf_range(0, card_hand.hand_limit - 1)
		draw_pile.append(card_array.get(random_num))
	return draw_pile

func _get_tres_file_and_apply(card : Node2D) -> void:
	var card_to_apply = card_dictionary.get(card)
	# TODO whatever the fuck is needed here to deal with .tres files, that shit is magic to me
	pass
