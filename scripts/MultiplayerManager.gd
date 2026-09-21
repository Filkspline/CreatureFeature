extends Node

signal session_created(session_id: String)
signal session_joined
signal session_left
signal connection_error(message: String)

@onready var tube_client: TubeClient = $TubeClient


func _ready():
	tube_client.session_created.connect(_on_session_created)
	tube_client.session_joined.connect(_on_session_joined)
	tube_client.session_left.connect(_on_session_left)
	tube_client.error_raised.connect(_on_error_raised)


func host_game():
	print("=== TUBE DEBUG ===")
	print("Context: ", tube_client.context)
	print("App ID: '", tube_client.context.app_id, "'")
	print("App ID length: ", tube_client.context.app_id.length())
	print("Context valid: ", tube_client.context.is_valid())
	print("==================")

	tube_client.create_session()


func join_game(session_id: String):
	print("Joining multiplayer session: ", session_id)
	tube_client.join_session(session_id)


func leave_game():
	tube_client.leave_session()


func _on_session_created():
	print("Session created!")
	print("Session ID: ", tube_client.session_id)

	session_created.emit(tube_client.session_id)


func _on_session_joined():
	print("Successfully joined session!")

	session_joined.emit()


func _on_session_left():
	print("Left multiplayer session.")

	session_left.emit()


func _on_error_raised(code, message):
	print("Tube error: ", code, " - ", message)

	connection_error.emit(message)
