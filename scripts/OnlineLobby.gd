extends Control

# ──────────────────────────────────────────────────────────────────
#  OnlineLobby
#
#  Host or join a session, then hand off to player select.
#
#  Tube's whole premise is a short session id that the players pass to each
#  other themselves: whoever hosts shows the id, whoever joins types it in.
#  Once the two peers are actually connected this screen sets the online role
#  and changes to player select, which is the first screen that has to know
#  anything about online play.
#
#  Two deliberate choices here:
#
#  * The session id is shown the moment HOST is pressed, not when the session
#    reports itself created. With trackers configured, "created" only arrives
#    once a tracker WebSocket is open, and a host staring at "creating..."
#    with no id to share has nothing to do - the id already exists by then.
#  * The screen never changes scene on its own except to hand off to player
#    select. An opponent dropping puts the lobby back into a state where the
#    player can host again or join, rather than throwing them back to the menu.
# ──────────────────────────────────────────────────────────────────

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const PLAYER_SELECT_SCENE := "res://scenes/player_select.tscn"

## How long to wait before this machine changes to player select after a peer
## connects. Both peers change scene on their own (the RPCs that sync the select
## screen are sent from the new scene), and a peer that is still mid-transition
## drops them, so they are given a moment to arrive.
@export var handoff_delay : float = 0.6

@onready var session_input: LineEdit = $SessionRow/SessionInput
@onready var copy_button: Button = $SessionRow/CopyButton
@onready var host_button: Button = $Buttons/HostButton
@onready var join_button: Button = $Buttons/JoinButton
@onready var status_label: Label = $StatusLabel
@onready var back_button: Button = $BackButton

var _hosting := false
var _handing_off := false


func _ready():
	MultiplayerManager.session_created.connect(_on_session_created)
	MultiplayerManager.session_joined.connect(_on_session_joined)
	MultiplayerManager.session_left.connect(_on_session_left)
	MultiplayerManager.connection_error.connect(_on_connection_error)
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)

	# Coming back here with a session already open (only possible if the player
	# came back to change their mind mid-lobby) should look like it.
	if MultiplayerManager.is_online():
		_show_hosting(MultiplayerManager.session_id, "Still in a session. Waiting for the other player.")
	else:
		_set_status("HOST A GAME, OR TYPE A SESSION ID AND JOIN.")
		host_button.grab_focus()

	# Navigation here is Godot's own focus handling, the same as the settings
	# screen: gaining focus sounds like a hover, pressing sounds like a select.
	call_deferred("_connect_ui_sounds", self)


# ── Buttons ──

func _on_host_button_pressed():
	if _handing_off:
		return
	_hosting = true
	SfxManager.play_ui_select()
	_set_status("OPENING A SESSION...")
	MultiplayerManager.host_game()
	# host_game() has already generated the id, so it can go on screen now
	# instead of when the trackers confirm the session.
	if not MultiplayerManager.session_id.is_empty():
		_show_hosting(MultiplayerManager.session_id, "OPENING A SESSION...")


func _on_join_button_pressed():
	if _handing_off:
		return
	var code := session_input.text.strip_edges()
	if code.is_empty():
		SfxManager.play_ui_hover()
		_set_status("TYPE THE OTHER PLAYER'S SESSION ID FIRST.")
		session_input.grab_focus()
		return
	_hosting = false
	SfxManager.play_ui_select()
	_set_status("JOINING...")
	MultiplayerManager.join_game(code)


func _on_copy_button_pressed():
	if MultiplayerManager.session_id.is_empty():
		return
	SfxManager.play_ui_select()
	DisplayServer.clipboard_set(MultiplayerManager.session_id)
	_set_status("SESSION ID COPIED. SEND IT TO THE OTHER PLAYER.")


func _on_back_button_pressed() -> void:
	# Leaving the screen without leaving the session would keep the lobby open
	# on the relay for whoever joins that session id next.
	SfxManager.play_ui_select()
	MultiplayerManager.leave_game()
	SceneTransition.change_scene(MAIN_MENU_SCENE)


# ── Session state ──

func _on_session_created(session_id: String):
	_show_hosting(session_id, "SESSION OPEN. SEND THE ID TO THE OTHER PLAYER.")


func _on_session_joined():
	_set_status("JOINED. WAITING FOR THE HOST'S SESSION TO OPEN...")


func _on_peer_connected(peer_id):
	print("Opponent connected: ", peer_id)
	# The role is what every online screen reads: the session's server peer is
	# player 1, everyone else is player 2.
	GameManager.online_mode = true
	GameManager.online_player_id = 1 if MultiplayerManager.is_host() else 2
	print("Online player ID: ", GameManager.online_player_id)

	_set_status("OPPONENT CONNECTED. GOING TO INPUT SELECT...")
	_handing_off = true
	_set_buttons_enabled(false)
	await get_tree().create_timer(handoff_delay).timeout
	if not is_inside_tree():
		return
	SceneTransition.change_scene(PLAYER_SELECT_SCENE)


func _on_peer_disconnected(peer_id):
	print("Opponent disconnected: ", peer_id)
	if _handing_off:
		return
	SfxManager.play_ui_hover()
	if MultiplayerManager.is_host():
		# The session is still open, so the same player can rejoin with the
		# same id: keep it on screen and wait.
		_show_hosting(MultiplayerManager.session_id, "THE OTHER PLAYER LEFT. THE SESSION IS STILL OPEN.")
	else:
		_set_status("THE HOST LEFT. HOST A GAME, OR TYPE ANOTHER SESSION ID.")


func _on_session_left():
	if _handing_off:
		return
	_hosting = false
	_show_joinable()
	_set_status("LEFT THE SESSION. HOST A GAME, OR TYPE A SESSION ID AND JOIN.")


func _on_connection_error(message: String):
	# Whatever went wrong, the screen goes back to a state the player can act
	# in, with the reason spelled out above it.
	_handing_off = false
	_hosting = false
	_set_buttons_enabled(true)
	_show_joinable()
	_set_status("COULD NOT CONNECT: %s" % message.to_upper())


# ── Look ──

# Hosting: the field shows our own id (read-only, so it cannot be typed over
# by accident) and COPY appears next to it.
func _show_hosting(code: String, message: String) -> void:
	_hosting = true
	session_input.text = code
	session_input.editable = false
	session_input.placeholder_text = ""
	join_button.visible = false
	host_button.visible = true
	copy_button.visible = not code.is_empty()
	_set_status(message)


func _show_joinable() -> void:
	session_input.editable = true
	session_input.text = ""
	session_input.placeholder_text = "TYPE THE OTHER PLAYER'S SESSION ID"
	join_button.visible = true
	host_button.visible = true
	copy_button.visible = false


func _set_status(message: String) -> void:
	status_label.text = message


func _set_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	back_button.disabled = not enabled


# Walks the screen and wires the shared UI sounds onto every button, the same
# way the settings screen does.
func _connect_ui_sounds(node: Node) -> void:
	var button := node as Button
	if button and not button.pressed.is_connected(SfxManager.play_ui_select):
		button.pressed.connect(SfxManager.play_ui_select)
	var control := node as Control
	if control and control.focus_mode != Control.FOCUS_NONE:
		if not control.focus_entered.is_connected(SfxManager.play_ui_hover):
			control.focus_entered.connect(SfxManager.play_ui_hover)
	for child in node.get_children():
		_connect_ui_sounds(child)


func _process(_delta: float) -> void:
	if _handing_off:
		return
	# Confirm the focused control and back out, so the lobby is usable on a pad
	# like every other menu. The focused control answers ui_accept itself.
	if Input.is_action_just_pressed("MenuBack"):
		_on_back_button_pressed()
