extends Control

@onready var restart_label = $background/MarginContainer/VBoxContainer/HBoxContainer/restart_label
@onready var continue_label = $background/MarginContainer/VBoxContainer/HBoxContainer/continue_label
@onready var player_loss_label = $background/MarginContainer/VBoxContainer/HBoxContainer2/VBoxContainer/player_loss_label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#EventBus.game_ended.connect(_on_player_loss)
	#print_rich("[color=yellow][END SCREEN] Connections to 'game_ended': %s" % EventBus.game_ended.get_connections())
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_player_loss(loser_id: int) -> void:
	print_rich("[color=yellow][END SCREEN] Loser id: %s" % loser_id)
	match loser_id:
		1:
			player_loss_label.text = "PLAYER_ONE_LOST"
		2:
			player_loss_label.text = "PLAYER_TWO_LOST"
