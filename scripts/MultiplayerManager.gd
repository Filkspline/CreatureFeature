extends Node

# ──────────────────────────────────────────────────────────────────
#  MultiplayerManager (autoload)
#
#  Thin, game-facing wrapper around the Tube addon's TubeClient (see
#  addons/tube/README.md). Tube is a WebRTC peer-to-peer session layer:
#  the player who hosts creates a session and gets a short session ID to
#  share, everyone else joins with that ID. There is no server to deploy.
#
#  Tube sets up Godot's high-level MultiplayerAPI on the SceneTree root,
#  so once a session exists the rest of the game just uses normal RPCs.
#  This autoload exists so the rest of the game never has to know that:
#  menus talk in session_created / session_joined / peer_connected /
#  peer_disconnected / connection_error, and ask is_host()/is_online().
#
#  Two things it deliberately does NOT do: it never changes scene itself
#  (the screens decide that), and it never clears GameManager's online
#  state, because a match in progress still needs to know it is online
#  even if the peer link drops.
# ──────────────────────────────────────────────────────────────────

## Emitted when this peer has created a session (we are the host/server).
signal session_created(session_id: String)
## Emitted when this peer has successfully joined someone else's session.
signal session_joined
## Emitted when this peer has left, or the session closed underneath it.
signal session_left
## Emitted when a session could not be created/joined, or signalling failed.
signal connection_error(message: String)
## Another peer joined the session. Emitted on all peers.
signal peer_connected(peer_id)
## Another peer left (or its connection became unrecoverable). All peers.
signal peer_disconnected(peer_id)

@onready var tube_client: TubeClient = $TubeClient

## The ID of the session we are in, or "" when there is none. Known as soon as
## host_game() is called, which is why the lobby can show it before the session
## has finished opening.
var session_id: String = ""


func _ready():
	tube_client.session_created.connect(_on_session_created)
	tube_client.session_joined.connect(_on_session_joined)
	tube_client.session_left.connect(_on_session_left)
	tube_client.error_raised.connect(_on_error_raised)
	tube_client.peer_connected.connect(_on_peer_connected)
	tube_client.peer_disconnected.connect(_on_peer_disconnected)


# ── What the menus ask ──

## True while a session exists (creating, created, joining or joined).
func is_online() -> bool:
	return tube_client.state != TubeClient.State.IDLE


## True when this player is the one hosting: the session's server peer.
func is_host() -> bool:
	return tube_client.is_server


## The TubeClient state, for screens that want to say "creating..." vs "waiting".
func state() -> int:
	return tube_client.state


## Human-readable state, so every screen does not reinvent the same wording.
func state_text() -> String:
	match tube_client.state:
		TubeClient.State.CREATING_SESSION:
			return "Creating session..."
		TubeClient.State.SESSION_CREATED:
			return "Waiting for the other player to join..."
		TubeClient.State.JOINING_SESSION:
			return "Joining session..."
		TubeClient.State.SESSION_JOINED:
			return "Connected."
		_:
			return "Not in a session."


# ── Session control ──

func host_game():
	if is_online():
		# Creating a second session over a live one would leave the first one
		# open on the relay for whoever joins that ID next.
		connection_error.emit("Already in a session.")
		return
	print("=== TUBE DEBUG ===")
	print("Context: ", tube_client.context)
	print("App ID: '", tube_client.context.app_id, "'")
	print("App ID length: ", tube_client.context.app_id.length())
	print("Context valid: ", tube_client.context.is_valid())
	print("Trackers: ", tube_client.context.trackers_urls)
	print("STUN: ", tube_client.context.stun_servers_urls)
	print("==================")

	tube_client.create_session()
	# The ID exists from the moment create_session() runs, even though the
	# session only finishes opening when session_created arrives: the host needs
	# it early, because sharing it is the whole point of hosting.
	session_id = tube_client.session_id


func join_game(p_session_id: String):
	if is_online():
		connection_error.emit("Already in a session.")
		return
	var trimmed := p_session_id.strip_edges()
	if trimmed.is_empty():
		connection_error.emit("Enter a session ID.")
		return
	if not tube_client.context.is_session_id_valid(trimmed):
		connection_error.emit("Session IDs are %d characters long." % 5)
		return
	print("Joining multiplayer session: ", trimmed)
	tube_client.join_session(trimmed)
	session_id = trimmed


func leave_game():
	if not is_online():
		return
	tube_client.leave_session()


# ── Tube signals ──

func _on_session_created():
	print("Session created!")
	print("Session ID: ", tube_client.session_id)
	session_id = tube_client.session_id
	session_created.emit(session_id)


func _on_session_joined():
	print("Successfully joined session!")
	session_joined.emit()


func _on_session_left():
	print("Left multiplayer session.")
	session_id = ""
	# A closed session is not an online match any more, whichever screen is
	# open: otherwise the next player-select would wait for a peer that is gone.
	GameManager.clear_online_state()
	session_left.emit()


func _on_error_raised(code, message):
	print("Tube error: ", code, " - ", message)
	connection_error.emit(message)


func _on_peer_connected(peer_id):
	print("PEER CONNECTED: ", peer_id)
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id):
	print("PEER DISCONNECTED: ", peer_id)
	# An opponent vanishing mid-match is a forfeit, not a crash: whoever is still
	# here is sent to the victory screen as the winner, and the session closes.
	# Before a match starts (in the lobby) there is nobody to award the match to,
	# so the lobby gets the signal and shows its own "they left" state.
	if GameManager.online_mode:
		GameManager.win_id = GameManager.online_player_id
		print("Opponent gone - awarding the match to player %d" % GameManager.win_id)
		GameManager.clear_online_state()
		SceneTransition.change_scene("res://scenes/player_victory.tscn")
		return
	peer_disconnected.emit(peer_id)
