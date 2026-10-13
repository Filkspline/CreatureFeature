extends Control

var is_host := false
var opponent_joined := false

@onready var session_id_input: LineEdit = $SessionIDInput
@onready var status_label: Label = $StatusLabel


func _ready():
	MultiplayerManager.session_created.connect(_on_session_created)
	MultiplayerManager.session_joined.connect(_on_session_joined)
	MultiplayerManager.connection_error.connect(_on_connection_error)
	MultiplayerManager.peer_connected.connect(_on_peer_connected)

	status_label.text = "Choose Host Game or Join Game."


func _on_host_button_pressed():
	print("HOST BUTTON PRESSED")

	is_host = true
	status_label.text = "Creating game..."

	MultiplayerManager.host_game()


func _on_join_button_pressed():
	var session_id := session_id_input.text.strip_edges()

	if session_id.is_empty():
		status_label.text = "Enter a Session ID."
		return

	is_host = false
	status_label.text = "Joining game..."

	MultiplayerManager.join_game(session_id)


func _on_session_created(session_id: String):
	status_label.text = "Game created!\nSession ID: " + session_id


func _on_session_joined():
	status_label.text = "Joined game!"


func _on_peer_connected(peer_id):
	print("Opponent connected: ", peer_id)

	opponent_joined = true
	status_label.text = "Opponent connected!"

	GameManager.online_mode = true
	GameManager.online_player_id = 1 if multiplayer.is_server() else 2

	print("Online player ID: ", GameManager.online_player_id)

	SceneTransition.change_scene("res://scenes/player_select.tscn")

func _on_connection_error(message: String):
	status_label.text = "Error: " + message


func _on_back_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/main_menu.tscn")
