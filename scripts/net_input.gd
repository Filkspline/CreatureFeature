extends Node

# ──────────────────────────────────────────────────────────────────
#  NetInput (autoload) - lockstep input relay for online matches
#
#  TICK MODEL (deliberately simple - no clock estimation):
#    * Both machines announce themselves with a reliable "hello" and then a
#      reliable "ready", each retried until acknowledged. Tick 0 only begins once
#      both sides have each other's hello AND ready, so both start at tick 0
#      together rather than by coincidence.
#    * From then on both machines run the same ticks in the same order, and an
#      input sampled at tick N is applied at tick N + delay_frames on BOTH
#      machines. There is no offset between the counters, because the handshake
#      removes the reason for one.
#    * The first delay_frames ticks are pre-filled with "nothing pressed" for both
#      players on both machines, so the very first steps have inputs to run on.
#    * A tick only runs when both players' inputs for it are in hand. If the other
#      machine's are missing, this machine does not advance at all - a visible
#      stall instead of a divergence.
#
#  Inputs are sent "reliable" and ordered: a lockstep game cannot tolerate a lost
#  input packet, and reliable delivery is cheaper to reason about than redundancy.
#
#  STAGES: on entering the fight, five checks run and report pass/fail both in the
#  log and on screen, so a single run says which layer is broken.
# ──────────────────────────────────────────────────────────────────

const BASES: Array[String] = ["Left", "Right", "Up", "Down", "Normal", "Special", "Jump"]

const RPC_PATH := "/root/NetInput"

## Ticks of input delay, this machine's included.
@export var delay_frames : int = 5
@export var min_delay_frames : int = 2
@export var max_delay_frames : int = 12

@export_group("Debug")
## Master debug toggle: staged startup report on screen and in the log, plus
## packet and stall logging.
@export var debug : bool = true

@export_group("Desync check")
@export var checksum_interval_seconds : float = 0.5

## Stage names, in order.
const STAGES := [
	"1 session + roles",
	"2 fight scene + players",
	"3 hello round trip",
	"4 ready handshake",
	"5 inputs flowing",
]

var _tick : int = 0
var _scheduled : Dictionary = {}
var _held : Dictionary = {}
var _previous : Dictionary = {}
var _packets_sent : int = 0
var _packets_received : int = 0
var _highest_remote_tick : int = -1

var _stalled : bool = false
var _stall_seconds : float = 0.0
var _longest_stall : float = 0.0
var _stall_log_timer : float = 0.0

## Set once stage 4 passes and tick 0 has been run.
var _running : bool = false
var _hello_in : bool = false
var _hello_out : bool = false
var _ready_in : bool = false
var _ready_out : bool = false
var _handshake_timer : float = 0.0
var _checksum_timer : float = 0.0

## Per-stage result: -1 pending, 0 failed, 1 passed.
var _stages : Array[int] = [-1, -1, -1, -1, -1]
var _stage_notes : Array[String] = ["", "", "", "", ""]

var _indicator_layer : CanvasLayer
var _indicator : Label
var _stage_labels : Array[Label] = []


func _ready() -> void:
	_clear()
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)


func _physics_process(delta: float) -> void:
	if not active():
		return

	if fight_active() and not _running:
		_run_startup_stages()
		if not _running:
			_stalled = true
			_stall_seconds += delta
			_update_overlay()
			return

	# Sampling always happens, stalled or not, or nothing could ever unstick.
	_sample_and_send()

	_checksum_timer += delta
	if _checksum_timer >= checksum_interval_seconds:
		_checksum_timer = 0.0
		_exchange_checksum()

	if not _running:
		_stalled = true
		_update_overlay()
		return

	if ready_to_step():
		if _stalled and _stall_seconds > 0.05:
			_log("stall ended after %.2fs at tick %d" % [_stall_seconds, _tick])
		_stalled = false
		_stall_seconds = 0.0
		_stall_log_timer = 0.0
		_tick += 1
		_apply_scheduled()
	else:
		if not _stalled:
			_log("STALL at tick %d, waiting for tick %d" % [_tick, _tick + 1])
			_stall_seconds = 0.0
			_stall_log_timer = 0.0
		_stalled = true
		_stall_seconds += delta
		_longest_stall = maxf(_longest_stall, _stall_seconds)
		_stall_log_timer += delta
		if debug and _stall_log_timer >= 0.5:
			_stall_log_timer = 0.0
			_log_stall_detail()

	_update_overlay()


# ── Staged startup ──

func _run_startup_stages() -> void:
	_handshake_timer += get_physics_process_delta_time()

	# Stage 1: session, peer ids, roles.
	if _stages[0] != 1:
		var slot := GameManager.online_player_id
		if slot == 1 or slot == 2:
			_set_stage(0, 1, "me=P%d peer=%d role=%s" % [
				slot, multiplayer.get_unique_id(),
				"host" if multiplayer.is_server() else "client"
			])
		else:
			_set_stage(0, 0, "online_player_id is %d" % slot)
			return

	# Stage 2: fight scene and its two characters.
	if _stages[1] != 1:
		var scene_path := str(get_tree().current_scene.scene_file_path) if get_tree().current_scene else "<none>"
		var p1 := GameManager.p1_node
		var p2 := GameManager.p2_node
		if p1 == null or p2 == null:
			_set_stage(1, 0, "p1=%s p2=%s scene=%s" % [str(p1), str(p2), scene_path])
			return
		var p1_ok := p1.is_inside_tree() and p1.is_visible_in_tree()
		var p2_ok := p2.is_inside_tree() and p2.is_visible_in_tree()
		if not (p1_ok and p2_ok):
			_set_stage(1, 0, "in_tree/visible p1=%s p2=%s scene=%s" % [
				str(p1_ok), str(p2_ok), scene_path
			])
			return
		_set_stage(1, 1, "scene=%s p1=%s p2=%s" % [
			scene_path, p1.global_position, p2.global_position
		])

	# Stages 3 and 4: hello and ready, retried until both directions land.
	if not _hello_out:
		_hello.rpc(multiplayer.get_unique_id(), get_path())
		_hello_out = true
		_log("stage3: sent hello (rpc node path %s, my path %s)" % [RPC_PATH, str(get_path())])

	if _hello_in and _ready_out == false and _stages[2] == 1:
		_ready_to_fight.rpc(multiplayer.get_unique_id())
		_ready_out = true
		_log("stage4: sent ready")

	if _hello_in and _ready_in:
		_set_stage(3, 1, "both sides ready")
		_begin_running()
		return

	# Not ready yet: come back to this every frame, don't advance ticks.
	_stalled = true
	_stall_seconds += get_physics_process_delta_time()


func _begin_running() -> void:
	_running = true
	_tick = 0
	_scheduled.clear()
	_held.clear()
	_previous.clear()
	var window : int = maxi(delay_frames, 1)
	for t in range(1, window + 1):
		_schedule(t, 1, 0)
		_schedule(t, 2, 0)
	_log("stage5: BEGIN at tick 0, delay=%d, pre-filled ticks 1..%d" % [delay_frames, window])


@rpc("any_peer", "call_remote", "reliable")
func _hello(their_id: int, their_path: String) -> void:
	if not active():
		return
	_hello_in = true
	var peer_id := multiplayer.get_remote_sender_id()
	_set_stage(2, 1, "their id=%d sender=%d their node path=%s" % [their_id, peer_id, their_path])
	if debug:
		_log("stage3: HELLO RECEIVED from %d (node path %s)" % [their_id, their_path])
	# Acknowledge with our own hello if we have not sent one yet.
	if not _hello_out:
		_hello_out = true
		_hello.rpc(multiplayer.get_unique_id(), get_path())


@rpc("any_peer", "call_remote", "reliable")
func _ready_to_fight(their_id: int) -> void:
	if not active():
		return
	_ready_in = true
	if debug:
		_log("stage4: READY RECEIVED from %d" % their_id)


func _set_stage(index: int, result: int, note: String) -> void:
	if _stages[index] == result:
		return
	_stages[index] = result
	_stage_notes[index] = note
	var verdict := "pass" if result == 1 else "FAIL"
	_log("STAGE %s %s - %s" % [STAGES[index], verdict, note])
	_update_overlay()


# ── Fight queries ──

func active() -> bool:
	if not GameManager.online_mode:
		return false
	if GameManager.online_player_id != 1 and GameManager.online_player_id != 2:
		return false
	return multiplayer.has_multiplayer_peer()


func fight_active() -> bool:
	return active() and GameManager.p1_node != null and GameManager.p2_node != null


func active_for(_player_id: int) -> bool:
	return active()


func is_stalled() -> bool:
	return _stalled


func ready_to_step() -> bool:
	var slot : Dictionary = _scheduled.get(_tick + 1, {})
	return slot.has(1) and slot.has(2)


func held(player_id: int, base: String) -> bool:
	var index := BASES.find(base)
	if index < 0:
		return false
	var mask : int = _held.get(player_id, 0)
	return (mask & (1 << index)) != 0


func just_pressed(player_id: int, base: String) -> bool:
	var index := BASES.find(base)
	if index < 0:
		return false
	var now : int = _held.get(player_id, 0)
	var before : int = _previous.get(player_id, 0)
	var bit := 1 << index
	return (now & bit) != 0 and (before & bit) == 0


func longest_stall_seconds() -> float:
	return _longest_stall


func reset() -> void:
	_running = false
	_hello_in = false
	_hello_out = false
	_ready_in = false
	_ready_out = false
	_handshake_timer = 0.0
	_stages = [-1, -1, -1, -1, -1]
	_stage_notes = ["", "", "", "", ""]
	_clear()


func _on_peer_connected(_peer_id) -> void:
	reset()


func _on_peer_disconnected(_peer_id) -> void:
	reset()


# ── Relaying ──

func _sample_and_send() -> void:
	var player_id := GameManager.online_player_id
	var mask := 0
	for i in BASES.size():
		if Input.is_action_pressed(_action(BASES[i], player_id)):
			mask |= 1 << i
	_schedule(_tick + delay_frames, player_id, mask)
	if debug and _running:
		_log("send tick %d mask %d" % [_tick, mask])
	_send_input.rpc(_tick, mask)
	_packets_sent += 1


func _action(base: String, player_id: int) -> StringName:
	return StringName("%sP%d" % [base, player_id])


func _schedule(tick: int, player_id: int, mask: int) -> void:
	var slot : Dictionary = _scheduled.get(tick, {})
	slot[player_id] = mask
	_scheduled[tick] = slot


func _apply_scheduled() -> void:
	for tick in _scheduled.keys():
		if tick < _tick:
			_scheduled.erase(tick)
	var slot : Dictionary = _scheduled.get(_tick, {})
	if slot.is_empty():
		return
	for player_id in slot:
		_previous[player_id] = _held.get(player_id, 0)
		_held[player_id] = slot[player_id]


@rpc("any_peer", "call_remote", "reliable")
func _send_input(tick: int, mask: int) -> void:
	if not active():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player_id := 1 if sender == 1 else 2
	if player_id == GameManager.online_player_id:
		return

	_packets_received += 1
	_highest_remote_tick = maxi(_highest_remote_tick, tick)

	# No offset: after the ready handshake both machines are on the same tick
	# numbering, so an input sampled at their tick N is applied at N + delay here.
	var apply_at : int = tick + delay_frames
	var latest_allowed : int = _tick + delay_frames + 4
	if apply_at > latest_allowed:
		apply_at = latest_allowed
	if apply_at <= _tick:
		apply_at = _tick + 1
	_schedule(apply_at, player_id, mask)

	if debug and _running:
		_log("recv tick %d mask %d from P%d -> run at %d" % [tick, mask, player_id, apply_at])


func _clear() -> void:
	_scheduled.clear()
	_held.clear()
	_previous.clear()
	_stalled = false
	_stall_seconds = 0.0
	_stall_log_timer = 0.0


func _log(message: String) -> void:
	if not debug:
		return
	print("[NetInput P%d peer%d %s] %s" % [
		GameManager.online_player_id,
		multiplayer.get_unique_id(),
		"host" if multiplayer.is_server() else "client",
		message,
	])


func _log_stall_detail() -> void:
	var slot : Dictionary = _scheduled.get(_tick + 1, {})
	var missing := "none"
	if not slot.has(1) and not slot.has(2):
		missing = "P1+P2"
	elif not slot.has(1):
		missing = "P1"
	elif not slot.has(2):
		missing = "P2"
	var ticks : Array = _scheduled.keys()
	ticks.sort()
	_log("stalled %.2fs tick=%d waiting=%d missing=%s sent=%d recv=%d highest_remote=%d scheduled=%s" % [
		_stall_seconds, _tick, _tick + 1, missing,
		_packets_sent, _packets_received, _highest_remote_tick, str(ticks.slice(0, 8)),
	])


# ── On-screen overlay: stage list + live tick readout ──

func _update_overlay() -> void:
	if not active():
		if _indicator_layer != null:
			_indicator_layer.visible = false
		return
	if _indicator_layer == null:
		_build_overlay()

	_indicator_layer.visible = debug
	_indicator.visible = _stalled and (not _running or _stall_seconds >= 0.1)
	_indicator.text = "WAITING FOR OPPONENT..." if _running else "STARTING FIGHT..."

	for i in _stage_labels.size():
		var label := _stage_labels[i]
		var result := _stages[i]
		var mark := "[ ]" if result == -1 else ("[OK]" if result == 1 else "[X]")
		label.text = "%s %s  %s" % [mark, STAGES[i], _stage_notes[i]]
		if result == 0:
			label.add_theme_color_override("font_color", Color(1, 0.45, 0.45, 1))
		elif result == 1:
			label.add_theme_color_override("font_color", Color(0.6, 1, 0.6, 1))
		else:
			label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	_stage_labels[_stage_labels.size() - 1].text += "   tick=%d remote=%d sent=%d recv=%d %s" % [
		_tick, _highest_remote_tick, _packets_sent, _packets_received,
		"STALLED" if _stalled else "running",
	]


func _build_overlay() -> void:
	_indicator_layer = CanvasLayer.new()
	_indicator_layer.layer = 50
	add_child(_indicator_layer)

	var font : Font = preload("res://assets/card_assets/m3x6.ttf")
	var outline := Color(0.03529412, 0.03137255, 0.05490196, 1)

	_indicator = Label.new()
	_indicator.text = "STARTING FIGHT..."
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_indicator.offset_top = 8.0
	_indicator.offset_left = -220.0
	_indicator.offset_right = 220.0
	_indicator.add_theme_font_override("font", font)
	_indicator.add_theme_font_size_override("font_size", 16)
	_indicator.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_indicator.add_theme_constant_override("outline_size", 3)
	_indicator.add_theme_color_override("font_outline_color", outline)
	_indicator_layer.add_child(_indicator)

	_stage_labels.clear()
	for i in STAGES.size():
		var label := Label.new()
		label.text = "[ ] " + STAGES[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.offset_left = 4.0
		label.offset_top = 26.0 + i * 13.0
		label.offset_right = 636.0
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_outline_color", outline)
		_indicator_layer.add_child(label)
		_stage_labels.append(label)


# ── Desync check ──

func _exchange_checksum() -> void:
	if not _running:
		return
	_checksum.rpc(_tick, _state_checksum())


@rpc("any_peer", "call_remote", "unreliable")
func _checksum(their_tick: int, their_sum: int) -> void:
	if not _running:
		return
	if their_tick != _tick:
		return
	if their_sum == _state_checksum():
		return
	push_warning("[NetInput] DESYNC at tick %d" % _tick)
	for node in [GameManager.p1_node, GameManager.p2_node]:
		if node == null:
			print("  player node missing")
			continue
		print("  P%s pos=%s hp=%.2f state=%s" % [
			node.get("player_id"), str(node.get("global_position")),
			float(node.get("current_health")), str(node.get("state")),
		])


func _state_checksum() -> int:
	var parts := [GameManager.p1_rounds_won, GameManager.p2_rounds_won]
	for node in [GameManager.p1_node, GameManager.p2_node]:
		if node == null:
			parts.append(-1)
			continue
		var pos : Vector2 = node.get("global_position")
		parts.append(int(round(pos.x)))
		parts.append(int(round(pos.y)))
		parts.append(int(round(float(node.get("current_health")) * 10.0)))
		parts.append(int(node.get("state")))
	return hash(parts)
