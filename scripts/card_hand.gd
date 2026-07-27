extends Node2D

const UPGRADE_CARD = preload("res://scenes/upgrade_card.tscn")

var hand = self

var tween_matrix : Array[Array] # Continue this tomorrow, matrix of tweens etc

@export var hand_limit : int = 5
@export var hand_width : float = 150.0
@export var spread_curve: Curve
@export var height_curve: Curve
@export var rotation_curve: Curve

func draw_hand() -> void:
	for _x in hand_limit:
		var upgarde_card = UPGRADE_CARD.instantiate()
		add_child(upgarde_card)
	spread_cards()

func spread_cards() -> void:
	for card in hand.get_children():
		var hand_ratio = float(card.get_index())/float(self.get_child_count()-1)
		var destination = hand.global_transform
		
		# Calculates the locations of the card in the hand
		destination.origin.x += spread_curve.sample(hand_ratio) * hand_width
		destination.origin += height_curve.sample(hand_ratio) * (Vector2.UP * 15)
		
		# Sets the card locations the the assigned destinations
		card.transform = destination
		card.rotation = rotation_curve.sample(hand_ratio) * -0.3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	draw_hand()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
