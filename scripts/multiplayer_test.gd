extends Control

@onready var host_button: Button = $HostButton
@onready var session_id: LineEdit = $SessionID
@onready var join_button: Button = $JoinButton
@onready var status_label: Label = $StatusLabel


func _ready():
	MultiplayerManager.session_created.connect(_on_session_created)
	MultiplayerManager.session_joined.connect(_on_session_joined)
	MultiplayerManager.connection_error.connect(_on_connection_error)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)


func _on_host_pressed():
	status_label.text = "Creating session..."
	host_button.disabled = true

	MultiplayerManager.host_game()


func _on_join_pressed():
	var id = session_id.text.strip_edges()

	if id.is_empty():
		status_label.text = "Enter a session ID first."
		return

	status_label.text = "Joining..."
	join_button.disabled = true

	MultiplayerManager.join_game(id)


func _on_session_created(id: String):
	session_id.text = id
	status_label.text = "Session created! Give this ID to Player 2."

	print("MY SESSION ID: ", id)


func _on_session_joined():
	status_label.text = "Successfully joined!"


func _on_connection_error(message: String):
	status_label.text = "Connection error: " + message

	host_button.disabled = false
	join_button.disabled = false
