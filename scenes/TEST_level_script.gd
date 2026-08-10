extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.p1_node = get_node("Player")
	GameManager.p2_node = get_node("Player2")
